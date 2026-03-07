use std::path::Path;

use tree_sitter::Parser;

use super::{MethodDef, TypeDef, TypeDefKind};

/// Create a TypeScript tree-sitter parser.
pub fn new_parser() -> Result<Parser, Box<dyn std::error::Error>> {
    let mut parser = Parser::new();
    parser.set_language(&tree_sitter_typescript::LANGUAGE_TYPESCRIPT.into())?;
    Ok(parser)
}

/// Check if a TypeScript file is a test file.
pub fn is_test_file(path: &Path) -> bool {
    path.file_name()
        .and_then(|n| n.to_str())
        .is_some_and(|n| n.ends_with(".test.ts") || n.ends_with(".spec.ts"))
}

/// Parse a single TypeScript source file and extract type definitions.
pub fn parse_file(parser: &mut Parser, source: &str, file: &Path) -> Vec<TypeDef> {
    let Some(tree) = parser.parse(source, None) else {
        return Vec::new();
    };
    let mut types = Vec::new();
    extract_declarations(tree.root_node(), source.as_bytes(), file, &mut types);
    types
}

/// Extract import paths from a TypeScript source file.
///
/// Handles `import ... from "path"` and `import "path"` forms.
pub fn parse_imports(source: &str) -> Vec<String> {
    let mut parser = match new_parser() {
        Ok(p) => p,
        Err(_) => return Vec::new(),
    };
    let Some(tree) = parser.parse(source, None) else {
        return Vec::new();
    };
    let mut imports = Vec::new();
    let root = tree.root_node();
    let bytes = source.as_bytes();
    let mut cursor = root.walk();
    for child in root.children(&mut cursor) {
        if child.kind() != "import_statement" {
            continue;
        }
        if let Some(source_node) = child.child_by_field_name("source") {
            let text = node_text(source_node, bytes);
            let path = text.trim_matches(|c| c == '\'' || c == '"');
            imports.push(path.to_string());
        }
    }
    imports
}

fn extract_declarations(
    node: tree_sitter::Node,
    source: &[u8],
    file: &Path,
    types: &mut Vec<TypeDef>,
) {
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        match child.kind() {
            // Also handle `export_statement` wrapping a declaration
            "export_statement" => {
                extract_declarations(child, source, file, types);
            }
            "class_declaration" => {
                if let Some(td) = extract_class(child, source, file) {
                    types.push(td);
                }
            }
            "interface_declaration" => {
                if let Some(td) = extract_interface(child, source, file) {
                    types.push(td);
                }
            }
            "type_alias_declaration" => {
                if let Some(td) = extract_type_alias(child, source, file) {
                    types.push(td);
                }
            }
            _ => {}
        }
    }
}

fn extract_class(node: tree_sitter::Node, source: &[u8], file: &Path) -> Option<TypeDef> {
    let name_node = node.child_by_field_name("name")?;
    let name = node_text(name_node, source).to_string();

    let implements = extract_implements(node, source);
    let body = find_child_by_kind(node, "class_body")?;

    let mut fields = Vec::new();
    let mut methods = Vec::new();
    let mut body_cursor = body.walk();
    for member in body.children(&mut body_cursor) {
        match member.kind() {
            "public_field_definition" => {
                if let Some(field) = extract_field_definition(member, source) {
                    fields.push(field);
                }
            }
            "method_definition" => {
                if let Some(method) = extract_method_definition(member, source) {
                    methods.push(method);
                }
            }
            _ => {}
        }
    }

    Some(TypeDef {
        name,
        kind: TypeDefKind::Class,
        file: file.to_path_buf(),
        fields,
        methods,
        implements,
    })
}

fn extract_interface(node: tree_sitter::Node, source: &[u8], file: &Path) -> Option<TypeDef> {
    let name_node = node.child_by_field_name("name")?;
    let name = node_text(name_node, source).to_string();

    let body = find_child_by_kind(node, "object_type")
        .or_else(|| find_child_by_kind(node, "interface_body"))?;

    let mut methods = Vec::new();
    let mut fields = Vec::new();
    let mut body_cursor = body.walk();
    for member in body.children(&mut body_cursor) {
        match member.kind() {
            "method_signature" => {
                if let Some(method) = extract_method_signature(member, source) {
                    methods.push(method);
                }
            }
            "property_signature" => {
                if let Some(field) = extract_property_signature(member, source) {
                    fields.push(field);
                }
            }
            _ => {}
        }
    }

    Some(TypeDef {
        name,
        kind: TypeDefKind::Interface,
        file: file.to_path_buf(),
        fields,
        methods,
        implements: Vec::new(),
    })
}

/// Extract a type alias declaration as an interface (only if its value is an `object_type`).
///
/// Matches: `type Foo = { bar: string; baz(): void; }`
/// Skips unions, intersections, primitives, etc.
fn extract_type_alias(node: tree_sitter::Node, source: &[u8], file: &Path) -> Option<TypeDef> {
    let name_node = node.child_by_field_name("name")?;
    let name = node_text(name_node, source).to_string();

    // Only extract type aliases whose value is an object_type
    let value_node = node.child_by_field_name("value")?;
    if value_node.kind() != "object_type" {
        return None;
    }

    let mut methods = Vec::new();
    let mut fields = Vec::new();
    let mut cursor = value_node.walk();
    for member in value_node.children(&mut cursor) {
        match member.kind() {
            "method_signature" => {
                if let Some(method) = extract_method_signature(member, source) {
                    methods.push(method);
                }
            }
            "property_signature" => {
                if let Some(field) = extract_property_signature(member, source) {
                    fields.push(field);
                }
            }
            _ => {}
        }
    }

    Some(TypeDef {
        name,
        kind: TypeDefKind::Interface,
        file: file.to_path_buf(),
        fields,
        methods,
        implements: Vec::new(),
    })
}

/// Extract `implements` clause from a class declaration's `class_heritage`.
fn extract_implements(node: tree_sitter::Node, source: &[u8]) -> Vec<String> {
    let mut implements = Vec::new();
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        if child.kind() == "class_heritage" {
            let mut heritage_cursor = child.walk();
            for heritage_child in child.children(&mut heritage_cursor) {
                if heritage_child.kind() == "implements_clause" {
                    extract_type_names_from_clause(heritage_child, source, &mut implements);
                }
            }
        }
    }
    implements
}

/// Extract type names from an `implements_clause` node.
fn extract_type_names_from_clause(
    node: tree_sitter::Node,
    source: &[u8],
    names: &mut Vec<String>,
) {
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        // The type references inside implements_clause
        match child.kind() {
            "type_identifier" => {
                names.push(node_text(child, source).to_string());
            }
            "generic_type" => {
                // e.g., `SomeInterface<T>` — extract the base name
                if let Some(name_node) = child.child_by_field_name("name") {
                    names.push(node_text(name_node, source).to_string());
                } else if let Some(first) = find_child_by_kind(child, "type_identifier") {
                    names.push(node_text(first, source).to_string());
                }
            }
            _ => {}
        }
    }
}

/// Extract a field from `public_field_definition`.
fn extract_field_definition(node: tree_sitter::Node, source: &[u8]) -> Option<(String, String)> {
    let name_node = node.child_by_field_name("name")?;
    let name = node_text(name_node, source).to_string();
    let typ = node
        .child_by_field_name("type")
        .map(|n| extract_type_annotation_text(n, source))
        .unwrap_or_default();
    Some((name, typ))
}

/// Extract a property from `property_signature` (in interfaces).
fn extract_property_signature(node: tree_sitter::Node, source: &[u8]) -> Option<(String, String)> {
    let name_node = node.child_by_field_name("name")?;
    let name = node_text(name_node, source).to_string();
    let typ = node
        .child_by_field_name("type")
        .map(|n| extract_type_annotation_text(n, source))
        .unwrap_or_default();
    Some((name, typ))
}

/// Extract a method from `method_signature` (in interfaces).
fn extract_method_signature(node: tree_sitter::Node, source: &[u8]) -> Option<MethodDef> {
    let name_node = node.child_by_field_name("name")?;
    let params = node
        .child_by_field_name("parameters")
        .map(|p| extract_params(p, source))
        .unwrap_or_default();
    let returns = node
        .child_by_field_name("return_type")
        .map(|r| vec![extract_type_annotation_text(r, source)])
        .unwrap_or_default();
    Some(MethodDef {
        name: node_text(name_node, source).to_string(),
        params,
        returns,
    })
}

/// Extract a method from `method_definition` (in classes).
fn extract_method_definition(node: tree_sitter::Node, source: &[u8]) -> Option<MethodDef> {
    let name_node = node.child_by_field_name("name")?;
    let name = node_text(name_node, source).to_string();
    // Skip constructor
    if name == "constructor" {
        return None;
    }
    let params = node
        .child_by_field_name("parameters")
        .map(|p| extract_params(p, source))
        .unwrap_or_default();
    let returns = node
        .child_by_field_name("return_type")
        .map(|r| vec![extract_type_annotation_text(r, source)])
        .unwrap_or_default();
    Some(MethodDef {
        name,
        params,
        returns,
    })
}

fn extract_params(node: tree_sitter::Node, source: &[u8]) -> Vec<(String, String)> {
    let mut params = Vec::new();
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        match child.kind() {
            "required_parameter" | "optional_parameter" => {
                let name = child
                    .child_by_field_name("pattern")
                    .map(|n| node_text(n, source).to_string())
                    .unwrap_or_default();
                let typ = child
                    .child_by_field_name("type")
                    .map(|n| extract_type_annotation_text(n, source))
                    .unwrap_or_default();
                params.push((name, typ));
            }
            _ => {}
        }
    }
    params
}

/// Extract the text from a `type_annotation` node, stripping the leading `: `.
fn extract_type_annotation_text(node: tree_sitter::Node, source: &[u8]) -> String {
    let text = node_text(node, source);
    // type_annotation includes the `: ` prefix; strip it
    text.trim_start_matches(':').trim().to_string()
}

fn find_child_by_kind<'a>(node: tree_sitter::Node<'a>, kind: &str) -> Option<tree_sitter::Node<'a>> {
    let mut cursor = node.walk();
    let result = node.children(&mut cursor).find(|c| c.kind() == kind);
    result
}

fn node_text<'a>(node: tree_sitter::Node, source: &'a [u8]) -> &'a str {
    node.utf8_text(source).unwrap_or("")
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;

    fn parse(src: &str) -> Vec<TypeDef> {
        let mut parser = new_parser().unwrap();
        parse_file(&mut parser, src, &PathBuf::from("test.ts"))
    }

    #[test]
    fn test_class_extraction() {
        let src = r#"
class Order {
    id: string;
    total: number;

    save(): void {}
    cancel(reason: string): boolean { return true; }
}
"#;
        let types = parse(src);
        assert_eq!(types.len(), 1, "expected 1 type");

        let order = &types[0];
        assert_eq!(order.name, "Order");
        assert_eq!(order.kind, TypeDefKind::Class);
        assert_eq!(order.fields.len(), 2);
        assert_eq!(order.fields[0].0, "id");
        assert_eq!(order.fields[1].0, "total");
        // Methods (constructor is excluded by the extractor)
        assert_eq!(order.methods.len(), 2);
        assert_eq!(order.methods[0].name, "save");
        assert_eq!(order.methods[1].name, "cancel");
        assert_eq!(order.methods[1].params.len(), 1);
        assert_eq!(order.methods[1].params[0].0, "reason");
    }

    #[test]
    fn test_interface_extraction() {
        let src = r#"
interface OrderRepository {
    save(order: Order): void;
    findById(id: string): Order;
}
"#;
        let types = parse(src);
        assert_eq!(types.len(), 1);

        let repo = &types[0];
        assert_eq!(repo.name, "OrderRepository");
        assert_eq!(repo.kind, TypeDefKind::Interface);
        assert!(repo.fields.is_empty());
        assert_eq!(repo.methods.len(), 2);

        let save = &repo.methods[0];
        assert_eq!(save.name, "save");
        assert_eq!(save.params.len(), 1);
        assert_eq!(save.params[0].0, "order");
        assert_eq!(save.params[0].1, "Order");
        assert_eq!(save.returns, vec!["void".to_string()]);

        let find = &repo.methods[1];
        assert_eq!(find.name, "findById");
        assert_eq!(find.params.len(), 1);
        assert_eq!(find.params[0].0, "id");
        assert_eq!(find.params[0].1, "string");
        assert_eq!(find.returns, vec!["Order".to_string()]);
    }

    #[test]
    fn test_type_alias_extraction() {
        let src = r#"
type UserService = {
    name: string;
    age: number;
    greet(msg: string): string;
};
"#;
        let types = parse(src);


        assert_eq!(types.len(), 1);

        let svc = &types[0];
        assert_eq!(svc.name, "UserService");
        assert_eq!(svc.kind, TypeDefKind::Interface);
        assert_eq!(svc.fields.len(), 2);
        assert_eq!(svc.fields[0].0, "name");
        assert_eq!(svc.fields[0].1, "string");
        assert_eq!(svc.fields[1].0, "age");
        assert_eq!(svc.fields[1].1, "number");
        assert_eq!(svc.methods.len(), 1);
        assert_eq!(svc.methods[0].name, "greet");
        assert_eq!(svc.methods[0].params.len(), 1);
        assert_eq!(svc.methods[0].params[0].0, "msg");
        assert_eq!(svc.methods[0].params[0].1, "string");
        assert_eq!(svc.methods[0].returns, vec!["string".to_string()]);
        assert!(svc.implements.is_empty());
    }

    #[test]
    fn test_type_alias_union_skipped() {
        // Non-object type aliases should be ignored
        let src = r#"
type Status = "active" | "inactive";
type ID = string;
"#;
        let types = parse(src);


        assert_eq!(types.len(), 0, "union and primitive type aliases should be skipped");
    }

    #[test]
    fn test_implements_clause() {
        let src = r#"
interface Repository {
    save(item: Item): void;
}

class PostgresRepository implements Repository {
    save(item: Item): void {}
}
"#;
        let types = parse(src);


        assert_eq!(types.len(), 2);

        let repo_iface = types.iter().find(|t| t.name == "Repository").expect("Repository not found");
        assert_eq!(repo_iface.kind, TypeDefKind::Interface);
        assert!(repo_iface.implements.is_empty());

        let pg_repo = types.iter().find(|t| t.name == "PostgresRepository").expect("PostgresRepository not found");
        assert_eq!(pg_repo.kind, TypeDefKind::Class);
        assert_eq!(pg_repo.implements.len(), 1);
        assert_eq!(pg_repo.implements[0], "Repository");
    }

    #[test]
    fn test_export_wrapping() {
        let src = r#"
export class OrderService {
    process(id: string): void {}
}

export interface OrderPort {
    process(id: string): void;
}

export type OrderConfig = {
    timeout: number;
    retries: number;
};
"#;
        let types = parse(src);


        assert_eq!(types.len(), 3, "expected exported class, interface, and type alias");

        let svc = types.iter().find(|t| t.name == "OrderService").expect("OrderService not found");
        assert_eq!(svc.kind, TypeDefKind::Class);
        assert_eq!(svc.methods.len(), 1);
        assert_eq!(svc.methods[0].name, "process");

        let port = types.iter().find(|t| t.name == "OrderPort").expect("OrderPort not found");
        assert_eq!(port.kind, TypeDefKind::Interface);
        assert_eq!(port.methods.len(), 1);

        let config = types.iter().find(|t| t.name == "OrderConfig").expect("OrderConfig not found");
        assert_eq!(config.kind, TypeDefKind::Interface);
        assert_eq!(config.fields.len(), 2);
        assert_eq!(config.fields[0].0, "timeout");
        assert_eq!(config.fields[1].0, "retries");
    }

    #[test]
    fn test_multiple_types() {
        let src = r#"
interface Logger {
    log(message: string): void;
}

class ConsoleLogger implements Logger {
    log(message: string): void {}
}

type AppConfig = {
    debug: boolean;
    logLevel: string;
};

class App {
    config: AppConfig;
    start(): void {}
}
"#;
        let types = parse(src);


        assert_eq!(types.len(), 4, "expected Logger, ConsoleLogger, AppConfig, App");

        let logger = types.iter().find(|t| t.name == "Logger").expect("Logger not found");
        assert_eq!(logger.kind, TypeDefKind::Interface);
        assert_eq!(logger.methods.len(), 1);

        let console_logger = types.iter().find(|t| t.name == "ConsoleLogger").expect("ConsoleLogger not found");
        assert_eq!(console_logger.kind, TypeDefKind::Class);
        assert_eq!(console_logger.implements, vec!["Logger".to_string()]);
        assert_eq!(console_logger.methods.len(), 1);

        let config = types.iter().find(|t| t.name == "AppConfig").expect("AppConfig not found");
        assert_eq!(config.kind, TypeDefKind::Interface);
        assert_eq!(config.fields.len(), 2);

        let app = types.iter().find(|t| t.name == "App").expect("App not found");
        assert_eq!(app.kind, TypeDefKind::Class);
        assert_eq!(app.fields.len(), 1);
        assert_eq!(app.fields[0].0, "config");
        assert_eq!(app.methods.len(), 1);
        assert_eq!(app.methods[0].name, "start");
    }

    #[test]
    fn test_parse_imports() {
        let src = r#"
import { Order } from '../domain/order';
import { OrderRepository } from "../port/repository";
import express from 'express';

export class OrderController {}
"#;
        let imports = parse_imports(src);
        assert_eq!(imports, vec![
            "../domain/order",
            "../port/repository",
            "express",
        ]);
    }
}

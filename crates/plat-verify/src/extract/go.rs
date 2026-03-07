use std::path::Path;

use tree_sitter::Parser;

use super::{MethodDef, TypeDef, TypeDefKind};

/// Create a Go tree-sitter parser.
pub fn new_parser() -> Result<Parser, Box<dyn std::error::Error>> {
    let mut parser = Parser::new();
    parser.set_language(&tree_sitter_go::LANGUAGE.into())?;
    Ok(parser)
}

/// Check if a Go file is a test file.
pub fn is_test_file(path: &Path) -> bool {
    path.file_name()
        .and_then(|n| n.to_str())
        .is_some_and(|n| n.ends_with("_test.go"))
}

/// Parse a single Go source file and extract type definitions.
pub fn parse_file(parser: &mut Parser, source: &str, file: &Path) -> Vec<TypeDef> {
    let Some(tree) = parser.parse(source, None) else {
        return Vec::new();
    };
    let mut types = Vec::new();
    let root_node = tree.root_node();
    extract_type_declarations(root_node, source.as_bytes(), file, &mut types);
    extract_method_receivers(root_node, source.as_bytes(), &mut types);
    types
}

/// Extract import paths from a Go source file.
///
/// Handles both single imports (`import "path"`) and grouped imports
/// (`import ("path1"\n"path2")`).
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
        if child.kind() != "import_declaration" {
            continue;
        }
        let mut inner_cursor = child.walk();
        for spec in child.children(&mut inner_cursor) {
            match spec.kind() {
                "import_spec" => {
                    if let Some(path) = extract_import_path(spec, bytes) {
                        imports.push(path);
                    }
                }
                "import_spec_list" => {
                    let mut list_cursor = spec.walk();
                    for item in spec.children(&mut list_cursor) {
                        if item.kind() == "import_spec" {
                            if let Some(path) = extract_import_path(item, bytes) {
                                imports.push(path);
                            }
                        }
                    }
                }
                _ => {}
            }
        }
    }
    imports
}

fn extract_import_path(node: tree_sitter::Node, source: &[u8]) -> Option<String> {
    let path_node = node.child_by_field_name("path")?;
    let text = node_text(path_node, source);
    // Strip quotes
    Some(text.trim_matches('"').to_string())
}

fn extract_type_declarations(
    node: tree_sitter::Node,
    source: &[u8],
    file: &Path,
    types: &mut Vec<TypeDef>,
) {
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        if child.kind() != "type_declaration" {
            continue;
        }
        let mut spec_cursor = child.walk();
        for spec in child.children(&mut spec_cursor) {
            if spec.kind() != "type_spec" {
                continue;
            }
            let name_node = match spec.child_by_field_name("name") {
                Some(n) => n,
                None => continue,
            };
            let name = node_text(name_node, source).to_string();
            let type_node = match spec.child_by_field_name("type") {
                Some(n) => n,
                None => continue,
            };

            match type_node.kind() {
                "struct_type" => {
                    let fields = extract_struct_fields(type_node, source);
                    types.push(TypeDef {
                        name,
                        kind: TypeDefKind::Struct,
                        file: file.to_path_buf(),
                        fields,
                        methods: Vec::new(),
                        implements: Vec::new(),
                    });
                }
                "interface_type" => {
                    let methods = extract_interface_methods(type_node, source);
                    types.push(TypeDef {
                        name,
                        kind: TypeDefKind::Interface,
                        file: file.to_path_buf(),
                        fields: Vec::new(),
                        methods,
                        implements: Vec::new(),
                    });
                }
                _ => {
                    // Simple named type: `type Foo string`, `type Bar int`
                    // Treat as a fieldless struct (for model existence checks)
                    types.push(TypeDef {
                        name,
                        kind: TypeDefKind::Struct,
                        file: file.to_path_buf(),
                        fields: Vec::new(),
                        methods: Vec::new(),
                        implements: Vec::new(),
                    });
                }
            }
        }
    }
}

fn extract_struct_fields(node: tree_sitter::Node, source: &[u8]) -> Vec<(String, String)> {
    let mut fields = Vec::new();
    let Some(field_list) = find_child_by_kind(node, "field_declaration_list") else {
        return fields;
    };
    let mut cursor = field_list.walk();
    for field_decl in field_list.children(&mut cursor) {
        if field_decl.kind() != "field_declaration" {
            continue;
        }
        let name = field_decl
            .child_by_field_name("name")
            .map(|n| node_text(n, source).to_string());
        let typ = field_decl
            .child_by_field_name("type")
            .map(|n| node_text(n, source).to_string());
        if let (Some(name), Some(typ)) = (name, typ) {
            fields.push((name, typ));
        }
    }
    fields
}

fn extract_interface_methods(node: tree_sitter::Node, source: &[u8]) -> Vec<MethodDef> {
    let mut methods = Vec::new();
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        if child.kind() == "method_elem" || child.kind() == "method_spec" {
            if let Some(method) = parse_method_spec(child, source) {
                methods.push(method);
            }
        }
    }
    methods
}

fn parse_method_spec(node: tree_sitter::Node, source: &[u8]) -> Option<MethodDef> {
    let name = node.child_by_field_name("name")?;
    let params = node
        .child_by_field_name("parameters")
        .map(|p| extract_params(p, source))
        .unwrap_or_default();
    let returns = node
        .child_by_field_name("result")
        .map(|r| extract_return_types(r, source))
        .unwrap_or_default();
    Some(MethodDef {
        name: node_text(name, source).to_string(),
        params,
        returns,
    })
}

/// Attach methods defined with receivers to the corresponding struct type.
fn extract_method_receivers(
    root: tree_sitter::Node,
    source: &[u8],
    types: &mut [TypeDef],
) {
    let mut cursor = root.walk();
    for child in root.children(&mut cursor) {
        if child.kind() != "function_declaration" && child.kind() != "method_declaration" {
            continue;
        }
        // method_declaration has a receiver
        let Some(receiver_node) = child.child_by_field_name("receiver") else {
            continue;
        };
        let receiver_type = extract_receiver_type(receiver_node, source);
        let Some(recv_name) = receiver_type else {
            continue;
        };
        let Some(name_node) = child.child_by_field_name("name") else {
            continue;
        };
        let method_name = node_text(name_node, source).to_string();
        let params = child
            .child_by_field_name("parameters")
            .map(|p| extract_params(p, source))
            .unwrap_or_default();
        let returns = child
            .child_by_field_name("result")
            .map(|r| extract_return_types(r, source))
            .unwrap_or_default();
        let method = MethodDef {
            name: method_name,
            params,
            returns,
        };
        // Attach to existing type or create a new one
        if let Some(td) = types.iter_mut().find(|t| t.name == recv_name) {
            td.methods.push(method);
        }
    }
}

fn extract_receiver_type(node: tree_sitter::Node, source: &[u8]) -> Option<String> {
    // receiver: parameter_list containing a single parameter_declaration
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        if child.kind() == "parameter_declaration" {
            if let Some(type_node) = child.child_by_field_name("type") {
                let text = node_text(type_node, source);
                // Strip pointer: *Foo -> Foo
                return Some(text.trim_start_matches('*').to_string());
            }
        }
    }
    None
}

fn extract_params(node: tree_sitter::Node, source: &[u8]) -> Vec<(String, String)> {
    let mut params = Vec::new();
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        if child.kind() == "parameter_declaration" {
            let name = child
                .child_by_field_name("name")
                .map(|n| node_text(n, source).to_string())
                .unwrap_or_default();
            let typ = child
                .child_by_field_name("type")
                .map(|n| node_text(n, source).to_string())
                .unwrap_or_default();
            params.push((name, typ));
        }
    }
    params
}

fn extract_return_types(node: tree_sitter::Node, source: &[u8]) -> Vec<String> {
    match node.kind() {
        "parameter_list" => {
            // (Type1, Type2) form
            let mut types = Vec::new();
            let mut cursor = node.walk();
            for child in node.children(&mut cursor) {
                if child.kind() == "parameter_declaration" {
                    if let Some(t) = child.child_by_field_name("type") {
                        types.push(node_text(t, source).to_string());
                    } else {
                        // unnamed return: the whole node text is the type
                        types.push(node_text(child, source).to_string());
                    }
                }
            }
            types
        }
        _ => {
            // Single return type
            vec![node_text(node, source).to_string()]
        }
    }
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
        parse_file(&mut parser, src, &PathBuf::from("test.go"))
    }

    #[test]
    fn test_struct_extraction() {
        let src = r#"
package domain

type Order struct {
    ID     string
    Total  float64
    Status OrderStatus
}
"#;
        let types = parse(src);
        assert_eq!(types.len(), 1, "expected 1 type");

        let order = &types[0];
        assert_eq!(order.name, "Order");
        assert_eq!(order.kind, TypeDefKind::Struct);
        assert_eq!(order.fields.len(), 3);
        assert_eq!(order.fields[0], ("ID".to_string(), "string".to_string()));
        assert_eq!(
            order.fields[1],
            ("Total".to_string(), "float64".to_string())
        );
        assert_eq!(
            order.fields[2],
            ("Status".to_string(), "OrderStatus".to_string())
        );
        assert!(order.methods.is_empty());
    }

    #[test]
    fn test_interface_extraction() {
        let src = r#"
package port

type OrderRepository interface {
    Save(order Order) error
    FindById(id string) (Order, error)
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
        assert_eq!(save.name, "Save");
        assert_eq!(save.params.len(), 1);
        assert_eq!(
            save.params[0],
            ("order".to_string(), "Order".to_string())
        );
        assert_eq!(save.returns, vec!["error".to_string()]);

        let find = &repo.methods[1];
        assert_eq!(find.name, "FindById");
        assert_eq!(find.params.len(), 1);
        assert_eq!(find.params[0], ("id".to_string(), "string".to_string()));
        assert_eq!(
            find.returns,
            vec!["Order".to_string(), "error".to_string()]
        );
    }

    #[test]
    fn test_method_receiver() {
        let src = r#"
package infra

type PostgresOrderRepo struct {
    db *sql.DB
}

func (r *PostgresOrderRepo) Save(order Order) error {
    return nil
}

func (r *PostgresOrderRepo) FindById(id string) (Order, error) {
    return Order{}, nil
}
"#;
        let types = parse(src);
        assert_eq!(types.len(), 1);

        let repo = &types[0];
        assert_eq!(repo.name, "PostgresOrderRepo");
        assert_eq!(repo.kind, TypeDefKind::Struct);

        // The struct has one field: db *sql.DB
        assert_eq!(repo.fields.len(), 1);
        assert_eq!(repo.fields[0].0, "db");

        // Two methods attached via receiver
        assert_eq!(repo.methods.len(), 2);

        let save = &repo.methods[0];
        assert_eq!(save.name, "Save");
        assert_eq!(save.params.len(), 1);
        assert_eq!(
            save.params[0],
            ("order".to_string(), "Order".to_string())
        );
        assert_eq!(save.returns, vec!["error".to_string()]);

        let find = &repo.methods[1];
        assert_eq!(find.name, "FindById");
        assert_eq!(find.params.len(), 1);
        assert_eq!(find.params[0], ("id".to_string(), "string".to_string()));
        assert_eq!(
            find.returns,
            vec!["Order".to_string(), "error".to_string()]
        );
    }

    #[test]
    fn test_empty_interface() {
        let src = r#"
package domain

type Any interface {}
"#;
        let types = parse(src);
        assert_eq!(types.len(), 1);

        let any = &types[0];
        assert_eq!(any.name, "Any");
        assert_eq!(any.kind, TypeDefKind::Interface);
        assert!(any.methods.is_empty());
        assert!(any.fields.is_empty());
    }

    #[test]
    fn test_multiple_types_in_one_file() {
        let src = r#"
package domain

type User struct {
    Name  string
    Email string
}

type UserRepository interface {
    Create(user User) error
    Delete(id string) error
}
"#;
        let types = parse(src);
        assert_eq!(types.len(), 2, "expected both struct and interface");

        let user = types.iter().find(|t| t.name == "User").expect("User not found");
        let repo = types
            .iter()
            .find(|t| t.name == "UserRepository")
            .expect("UserRepository not found");

        assert_eq!(user.kind, TypeDefKind::Struct);
        assert_eq!(user.fields.len(), 2);
        assert_eq!(user.fields[0], ("Name".to_string(), "string".to_string()));
        assert_eq!(
            user.fields[1],
            ("Email".to_string(), "string".to_string())
        );
        assert!(user.methods.is_empty());

        assert_eq!(repo.kind, TypeDefKind::Interface);
        assert!(repo.fields.is_empty());
        assert_eq!(repo.methods.len(), 2);
        assert_eq!(repo.methods[0].name, "Create");
        assert_eq!(repo.methods[1].name, "Delete");
    }

    #[test]
    fn test_parse_imports_grouped() {
        let src = r#"
package main

import (
    "fmt"
    "myapp/domain"
    "myapp/infra/postgres"
)

type Foo struct {}
"#;
        let imports = parse_imports(src);
        assert_eq!(imports, vec!["fmt", "myapp/domain", "myapp/infra/postgres"]);
    }

    #[test]
    fn test_parse_imports_single() {
        let src = r#"
package main

import "myapp/domain"

type Foo struct {}
"#;
        let imports = parse_imports(src);
        assert_eq!(imports, vec!["myapp/domain"]);
    }
}

use std::collections::HashMap;
use std::path::Path;

use tree_sitter::Parser;
use walkdir::WalkDir;

use super::{resolve_layer, FileFacts, MethodDef, TypeDef, TypeDefKind};

/// Extract facts from TypeScript source files.
pub fn extract(
    root: &Path,
    layer_dirs: &HashMap<String, String>,
) -> Result<Vec<FileFacts>, Box<dyn std::error::Error>> {
    let mut parser = Parser::new();
    let language = tree_sitter_typescript::LANGUAGE_TYPESCRIPT;
    parser.set_language(&language.into())?;

    let mut all_facts = Vec::new();

    for entry in WalkDir::new(root)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().map_or(false, |ext| ext == "ts"))
        .filter(|e| !is_test_file(e.path()))
    {
        let path = entry.path().to_path_buf();
        let source = std::fs::read_to_string(&path)?;
        let tree = parser
            .parse(&source, None)
            .ok_or_else(|| format!("failed to parse {}", path.display()))?;

        let mut types = Vec::new();
        let root_node = tree.root_node();

        extract_declarations(root_node, source.as_bytes(), &path, &mut types);

        let layer = resolve_layer(&path, root, layer_dirs);
        all_facts.push(FileFacts {
            path,
            layer,
            types,
        });
    }

    Ok(all_facts)
}

fn is_test_file(path: &Path) -> bool {
    path.file_name()
        .and_then(|n| n.to_str())
        .map_or(false, |n| n.ends_with(".test.ts") || n.ends_with(".spec.ts"))
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

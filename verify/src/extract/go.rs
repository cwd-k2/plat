use std::collections::HashMap;
use std::path::Path;

use tree_sitter::Parser;
use walkdir::WalkDir;

use super::{resolve_layer, FileFacts, MethodDef, TypeDef, TypeDefKind};

/// Extract facts from Go source files.
pub fn extract(
    root: &Path,
    layer_dirs: &HashMap<String, String>,
) -> Result<Vec<FileFacts>, Box<dyn std::error::Error>> {
    let mut parser = Parser::new();
    let language = tree_sitter_go::LANGUAGE;
    parser.set_language(&language.into())?;

    let mut all_facts = Vec::new();

    for entry in WalkDir::new(root)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().map_or(false, |ext| ext == "go"))
        .filter(|e| !is_test_file(e.path()))
    {
        let path = entry.path().to_path_buf();
        let source = std::fs::read_to_string(&path)?;
        let tree = parser
            .parse(&source, None)
            .ok_or_else(|| format!("failed to parse {}", path.display()))?;

        let mut types = Vec::new();
        let root_node = tree.root_node();

        extract_type_declarations(root_node, source.as_bytes(), &path, &mut types);
        extract_method_receivers(root_node, source.as_bytes(), &mut types);

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
        .map_or(false, |n| n.ends_with("_test.go"))
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
                _ => {}
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
        if child.kind() == "method_spec" {
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
    types: &mut Vec<TypeDef>,
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

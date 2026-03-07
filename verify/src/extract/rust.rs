use std::collections::HashMap;
use std::path::Path;

use tree_sitter::Parser;
use walkdir::WalkDir;

use super::{resolve_layer, FileFacts, MethodDef, TypeDef, TypeDefKind};

/// Extract facts from Rust source files.
pub fn extract(
    root: &Path,
    layer_dirs: &HashMap<String, String>,
) -> Result<Vec<FileFacts>, Box<dyn std::error::Error>> {
    let mut parser = Parser::new();
    let language = tree_sitter_rust::LANGUAGE;
    parser.set_language(&language.into())?;

    let mut all_facts = Vec::new();

    for entry in WalkDir::new(root)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().map_or(false, |ext| ext == "rs"))
        .filter(|e| !is_test_file(e.path()))
    {
        let path = entry.path().to_path_buf();
        let source = std::fs::read_to_string(&path)?;
        let tree = parser
            .parse(&source, None)
            .ok_or_else(|| format!("failed to parse {}", path.display()))?;

        let mut types = Vec::new();
        let root_node = tree.root_node();

        extract_struct_items(root_node, source.as_bytes(), &path, &mut types);
        extract_trait_items(root_node, source.as_bytes(), &path, &mut types);
        extract_impl_items(root_node, source.as_bytes(), &mut types);

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
    // Skip files under a `tests/` directory
    path.components().any(|c| c.as_os_str() == "tests")
}

/// Extract `struct_item` declarations from top-level or within modules.
fn extract_struct_items(
    node: tree_sitter::Node,
    source: &[u8],
    file: &Path,
    types: &mut Vec<TypeDef>,
) {
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        match child.kind() {
            "struct_item" => {
                if let Some(td) = extract_struct(child, source, file) {
                    types.push(td);
                }
            }
            // Recurse into non-test module bodies
            "mod_item" => {
                if !is_cfg_test_module(child, source) {
                    if let Some(body) = find_child_by_kind(child, "declaration_list") {
                        extract_struct_items(body, source, file, types);
                    }
                }
            }
            _ => {}
        }
    }
}

/// Extract `trait_item` declarations from top-level or within modules.
fn extract_trait_items(
    node: tree_sitter::Node,
    source: &[u8],
    file: &Path,
    types: &mut Vec<TypeDef>,
) {
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        match child.kind() {
            "trait_item" => {
                if let Some(td) = extract_trait(child, source, file) {
                    types.push(td);
                }
            }
            "mod_item" => {
                if !is_cfg_test_module(child, source) {
                    if let Some(body) = find_child_by_kind(child, "declaration_list") {
                        extract_trait_items(body, source, file, types);
                    }
                }
            }
            _ => {}
        }
    }
}

/// Extract `impl_item` blocks and wire up implements relationships.
fn extract_impl_items(
    node: tree_sitter::Node,
    source: &[u8],
    types: &mut Vec<TypeDef>,
) {
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        match child.kind() {
            "impl_item" => {
                extract_impl(child, source, types);
            }
            "mod_item" => {
                if !is_cfg_test_module(child, source) {
                    if let Some(body) = find_child_by_kind(child, "declaration_list") {
                        extract_impl_items(body, source, types);
                    }
                }
            }
            _ => {}
        }
    }
}

fn extract_struct(node: tree_sitter::Node, source: &[u8], file: &Path) -> Option<TypeDef> {
    let name_node = node.child_by_field_name("name")?;
    let name = node_text(name_node, source).to_string();

    let fields = find_child_by_kind(node, "field_declaration_list")
        .map(|fl| extract_fields(fl, source))
        .unwrap_or_default();

    Some(TypeDef {
        name,
        kind: TypeDefKind::Struct,
        file: file.to_path_buf(),
        fields,
        methods: Vec::new(),
        implements: Vec::new(),
    })
}

fn extract_trait(node: tree_sitter::Node, source: &[u8], file: &Path) -> Option<TypeDef> {
    let name_node = node.child_by_field_name("name")?;
    let name = node_text(name_node, source).to_string();

    let methods = find_child_by_kind(node, "declaration_list")
        .map(|dl| extract_trait_methods(dl, source))
        .unwrap_or_default();

    Some(TypeDef {
        name,
        kind: TypeDefKind::Trait,
        file: file.to_path_buf(),
        fields: Vec::new(),
        methods,
        implements: Vec::new(),
    })
}

/// Process an `impl_item`.
///
/// If it is a trait impl (`impl Trait for Type`), attach the trait name
/// to the struct's `implements` list and attach methods to the struct.
/// If it is an inherent impl (`impl Type`), attach methods to the struct.
fn extract_impl(
    node: tree_sitter::Node,
    source: &[u8],
    types: &mut Vec<TypeDef>,
) {
    let (trait_name, struct_name) = parse_impl_header(node, source);
    let Some(struct_name) = struct_name else {
        return;
    };

    // Extract methods from the impl body
    let methods = find_child_by_kind(node, "declaration_list")
        .map(|dl| extract_impl_methods(dl, source))
        .unwrap_or_default();

    // Find the struct in the types list
    let Some(td) = types.iter_mut().find(|t| t.name == struct_name) else {
        return;
    };

    // If this is a trait impl, record the implements relationship
    if let Some(trait_name) = trait_name {
        if !td.implements.contains(&trait_name) {
            td.implements.push(trait_name);
        }
    }

    // Attach methods
    td.methods.extend(methods);
}

/// Parse the header of an `impl_item` to extract the trait name and type name.
///
/// `impl Trait for Type` → (Some("Trait"), Some("Type"))
/// `impl Type`           → (None, Some("Type"))
fn parse_impl_header(
    node: tree_sitter::Node,
    source: &[u8],
) -> (Option<String>, Option<String>) {
    // Look for `trait` and `type` field names
    let trait_node = node.child_by_field_name("trait");
    let type_node = node.child_by_field_name("type");

    let trait_name = trait_node.map(|n| extract_type_name(n, source));
    let struct_name = type_node.map(|n| extract_type_name(n, source));

    (trait_name, struct_name)
}

/// Extract a type name from a type node, stripping generic parameters.
fn extract_type_name(node: tree_sitter::Node, source: &[u8]) -> String {
    match node.kind() {
        "type_identifier" => node_text(node, source).to_string(),
        "generic_type" => {
            // Extract the base type name from a generic type like `Foo<T>`
            node.child_by_field_name("type")
                .map(|n| node_text(n, source).to_string())
                .unwrap_or_else(|| {
                    find_child_by_kind(node, "type_identifier")
                        .map(|n| node_text(n, source).to_string())
                        .unwrap_or_else(|| node_text(node, source).to_string())
                })
        }
        "scoped_type_identifier" => {
            // e.g., `module::Type` — take the last segment
            node.child_by_field_name("name")
                .map(|n| node_text(n, source).to_string())
                .unwrap_or_else(|| node_text(node, source).to_string())
        }
        _ => node_text(node, source).to_string(),
    }
}

fn extract_fields(node: tree_sitter::Node, source: &[u8]) -> Vec<(String, String)> {
    let mut fields = Vec::new();
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        if child.kind() != "field_declaration" {
            continue;
        }
        let name = child
            .child_by_field_name("name")
            .map(|n| node_text(n, source).to_string());
        let typ = child
            .child_by_field_name("type")
            .map(|n| node_text(n, source).to_string());
        if let (Some(name), Some(typ)) = (name, typ) {
            fields.push((name, typ));
        }
    }
    fields
}

fn extract_trait_methods(node: tree_sitter::Node, source: &[u8]) -> Vec<MethodDef> {
    let mut methods = Vec::new();
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        if child.kind() == "function_signature_item" {
            if let Some(method) = parse_function_signature(child, source) {
                methods.push(method);
            }
        }
    }
    methods
}

fn extract_impl_methods(node: tree_sitter::Node, source: &[u8]) -> Vec<MethodDef> {
    let mut methods = Vec::new();
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        if child.kind() == "function_item" {
            if let Some(method) = parse_function_item(child, source) {
                methods.push(method);
            }
        }
    }
    methods
}

fn parse_function_signature(node: tree_sitter::Node, source: &[u8]) -> Option<MethodDef> {
    let name_node = node.child_by_field_name("name")?;
    let params = node
        .child_by_field_name("parameters")
        .map(|p| extract_params(p, source))
        .unwrap_or_default();
    let returns = node
        .child_by_field_name("return_type")
        .map(|r| vec![node_text(r, source).to_string()])
        .unwrap_or_default();
    Some(MethodDef {
        name: node_text(name_node, source).to_string(),
        params,
        returns,
    })
}

fn parse_function_item(node: tree_sitter::Node, source: &[u8]) -> Option<MethodDef> {
    let name_node = node.child_by_field_name("name")?;
    let params = node
        .child_by_field_name("parameters")
        .map(|p| extract_params(p, source))
        .unwrap_or_default();
    let returns = node
        .child_by_field_name("return_type")
        .map(|r| vec![node_text(r, source).to_string()])
        .unwrap_or_default();
    Some(MethodDef {
        name: node_text(name_node, source).to_string(),
        params,
        returns,
    })
}

fn extract_params(node: tree_sitter::Node, source: &[u8]) -> Vec<(String, String)> {
    let mut params = Vec::new();
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        match child.kind() {
            "parameter" => {
                let name = child
                    .child_by_field_name("pattern")
                    .map(|n| node_text(n, source).to_string())
                    .unwrap_or_default();
                let typ = child
                    .child_by_field_name("type")
                    .map(|n| node_text(n, source).to_string())
                    .unwrap_or_default();
                params.push((name, typ));
            }
            // Skip `self` parameters
            "self_parameter" => {}
            _ => {}
        }
    }
    params
}

/// Check whether a `mod_item` has a `#[cfg(test)]` attribute.
fn is_cfg_test_module(node: tree_sitter::Node, source: &[u8]) -> bool {
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        if child.kind() == "attribute_item" {
            let text = node_text(child, source);
            if text.contains("cfg") && text.contains("test") {
                return true;
            }
        }
    }
    false
}

fn find_child_by_kind<'a>(node: tree_sitter::Node<'a>, kind: &str) -> Option<tree_sitter::Node<'a>> {
    let mut cursor = node.walk();
    let result = node.children(&mut cursor).find(|c| c.kind() == kind);
    result
}

fn node_text<'a>(node: tree_sitter::Node, source: &'a [u8]) -> &'a str {
    node.utf8_text(source).unwrap_or("")
}

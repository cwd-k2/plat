use std::path::Path;

use tree_sitter::Parser;

use super::{MethodDef, TypeDef, TypeDefKind};

/// Create a Rust tree-sitter parser.
pub fn new_parser() -> Result<Parser, Box<dyn std::error::Error>> {
    let mut parser = Parser::new();
    parser.set_language(&tree_sitter_rust::LANGUAGE.into())?;
    Ok(parser)
}

/// Check if a Rust file is under a `tests/` directory (relative to source root).
pub fn is_test_file(path: &Path, root: &Path) -> bool {
    let rel = path.strip_prefix(root).unwrap_or(path);
    rel.components().any(|c| c.as_os_str() == "tests")
}

/// Parse a single Rust source file and extract type definitions.
pub fn parse_file(parser: &mut Parser, source: &str, file: &Path) -> Vec<TypeDef> {
    let Some(tree) = parser.parse(source, None) else {
        return Vec::new();
    };
    let mut types = Vec::new();
    let root_node = tree.root_node();
    extract_struct_items(root_node, source.as_bytes(), file, &mut types);
    extract_trait_items(root_node, source.as_bytes(), file, &mut types);
    extract_impl_items(root_node, source.as_bytes(), &mut types);
    types
}

/// Extract import paths from a Rust source file.
///
/// Collects paths from `use` declarations (e.g., `use crate::domain::Order;`).
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
    extract_use_declarations(root, bytes, &mut imports);
    imports
}

fn extract_use_declarations(node: tree_sitter::Node, source: &[u8], imports: &mut Vec<String>) {
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        match child.kind() {
            "use_declaration" => {
                // The argument field contains the use path tree
                if let Some(arg) = child.child_by_field_name("argument") {
                    let text = node_text(arg, source);
                    // Normalize: strip braces, split grouped imports
                    for path in normalize_use_path(text) {
                        imports.push(path);
                    }
                }
            }
            "mod_item" => {
                if !is_cfg_test_module(child, source) {
                    if let Some(body) = find_child_by_kind(child, "declaration_list") {
                        extract_use_declarations(body, source, imports);
                    }
                }
            }
            _ => {}
        }
    }
}

/// Normalize a Rust use path into one or more simple paths.
///
/// `crate::domain::Order` → `["crate::domain::Order"]`
/// `crate::domain::{Order, Money}` → `["crate::domain::Order", "crate::domain::Money"]`
fn normalize_use_path(path: &str) -> Vec<String> {
    let path = path.trim();
    if let Some(brace_start) = path.find('{') {
        let prefix = &path[..brace_start];
        let brace_end = path.rfind('}').unwrap_or(path.len());
        let inner = &path[brace_start + 1..brace_end];
        inner
            .split(',')
            .map(|s| format!("{}{}", prefix, s.trim()))
            .filter(|s| !s.ends_with("::"))
            .collect()
    } else {
        vec![path.to_string()]
    }
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
    types: &mut [TypeDef],
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
    types: &mut [TypeDef],
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
            if let Some(method) = parse_fn_node(child, source) {
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
            if let Some(method) = parse_fn_node(child, source) {
                methods.push(method);
            }
        }
    }
    methods
}

fn parse_fn_node(node: tree_sitter::Node, source: &[u8]) -> Option<MethodDef> {
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
///
/// In tree-sitter-rust, outer attributes like `#[cfg(test)]` appear as
/// preceding siblings of the `mod_item`, not as children.
fn is_cfg_test_module(node: tree_sitter::Node, source: &[u8]) -> bool {
    let mut sibling = node.prev_sibling();
    while let Some(s) = sibling {
        if s.kind() == "attribute_item" {
            let text = node_text(s, source);
            if text.contains("cfg") && text.contains("test") {
                return true;
            }
        } else {
            // Stop at non-attribute nodes
            break;
        }
        sibling = s.prev_sibling();
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

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;

    fn parse(src: &str) -> Vec<TypeDef> {
        let mut parser = new_parser().unwrap();
        parse_file(&mut parser, src, &PathBuf::from("test.rs"))
    }

    #[test]
    fn test_struct_extraction() {
        let src = r#"
pub struct Order {
    pub id: String,
    pub total: f64,
    pub status: OrderStatus,
}
"#;
        let types = parse(src);
        assert_eq!(types.len(), 1, "expected 1 type");

        let order = &types[0];
        assert_eq!(order.name, "Order");
        assert_eq!(order.kind, TypeDefKind::Struct);
        assert_eq!(order.fields.len(), 3);
        assert_eq!(order.fields[0], ("id".to_string(), "String".to_string()));
        assert_eq!(order.fields[1], ("total".to_string(), "f64".to_string()));
        assert_eq!(
            order.fields[2],
            ("status".to_string(), "OrderStatus".to_string())
        );
        assert!(order.methods.is_empty());
        assert!(order.implements.is_empty());
    }

    #[test]
    fn test_trait_extraction() {
        let src = r#"
pub trait OrderRepository {
    fn save(&self, order: Order) -> Result<(), Error>;
    fn find_by_id(&self, id: String) -> Result<Order, Error>;
}
"#;
        let types = parse(src);
        assert_eq!(types.len(), 1);

        let repo = &types[0];
        assert_eq!(repo.name, "OrderRepository");
        assert_eq!(repo.kind, TypeDefKind::Trait);
        assert!(repo.fields.is_empty());
        assert_eq!(repo.methods.len(), 2);

        let save = &repo.methods[0];
        assert_eq!(save.name, "save");
        assert_eq!(save.params.len(), 1);
        assert_eq!(
            save.params[0],
            ("order".to_string(), "Order".to_string())
        );
        assert_eq!(save.returns.len(), 1);

        let find = &repo.methods[1];
        assert_eq!(find.name, "find_by_id");
        assert_eq!(find.params.len(), 1);
        assert_eq!(find.params[0], ("id".to_string(), "String".to_string()));
        assert_eq!(find.returns.len(), 1);
    }

    #[test]
    fn test_impl_trait_for_struct() {
        let src = r#"
pub struct PostgresOrderRepo {
    db: PgPool,
}

pub trait OrderRepository {
    fn save(&self, order: Order) -> Result<(), Error>;
    fn find_by_id(&self, id: String) -> Result<Order, Error>;
}

impl OrderRepository for PostgresOrderRepo {
    fn save(&self, order: Order) -> Result<(), Error> {
        todo!()
    }

    fn find_by_id(&self, id: String) -> Result<Order, Error> {
        todo!()
    }
}
"#;
        let types = parse(src);
        assert_eq!(types.len(), 2, "expected struct and trait");

        let repo = types
            .iter()
            .find(|t| t.name == "PostgresOrderRepo")
            .expect("PostgresOrderRepo not found");
        assert_eq!(repo.kind, TypeDefKind::Struct);
        assert_eq!(repo.fields.len(), 1);
        assert_eq!(repo.fields[0], ("db".to_string(), "PgPool".to_string()));

        assert_eq!(repo.implements.len(), 1);
        assert_eq!(repo.implements[0], "OrderRepository");

        assert_eq!(repo.methods.len(), 2);
        assert_eq!(repo.methods[0].name, "save");
        assert_eq!(repo.methods[1].name, "find_by_id");

        let trait_def = types
            .iter()
            .find(|t| t.name == "OrderRepository")
            .expect("OrderRepository not found");
        assert_eq!(trait_def.kind, TypeDefKind::Trait);
        assert_eq!(trait_def.methods.len(), 2);
        assert!(trait_def.implements.is_empty());
    }

    #[test]
    fn test_inherent_impl() {
        let src = r#"
pub struct User {
    pub name: String,
    pub email: String,
}

impl User {
    pub fn new(name: String, email: String) -> Self {
        Self { name, email }
    }

    pub fn display_name(&self) -> String {
        self.name.clone()
    }
}
"#;
        let types = parse(src);
        assert_eq!(types.len(), 1);

        let user = &types[0];
        assert_eq!(user.name, "User");
        assert_eq!(user.kind, TypeDefKind::Struct);
        assert_eq!(user.fields.len(), 2);
        assert_eq!(user.fields[0], ("name".to_string(), "String".to_string()));
        assert_eq!(
            user.fields[1],
            ("email".to_string(), "String".to_string())
        );

        assert_eq!(user.methods.len(), 2);
        assert_eq!(user.methods[0].name, "new");
        assert_eq!(user.methods[1].name, "display_name");

        assert!(user.implements.is_empty());
    }

    #[test]
    fn test_cfg_test_skip() {
        let src = r#"
pub struct RealType {
    pub value: i32,
}

#[cfg(test)]
mod tests {
    pub struct TestOnlyType {
        pub dummy: String,
    }

    pub trait TestOnlyTrait {
        fn test_method(&self);
    }
}
"#;
        let types = parse(src);

        assert_eq!(types.len(), 1, "expected only RealType, test types should be skipped");
        assert_eq!(types[0].name, "RealType");
        assert_eq!(types[0].kind, TypeDefKind::Struct);
    }

    #[test]
    fn test_multiple_types() {
        let src = r#"
pub struct User {
    pub name: String,
    pub email: String,
}

pub struct Account {
    pub id: u64,
    pub owner: String,
}

pub trait UserRepository {
    fn create(&self, user: User) -> Result<(), Error>;
    fn delete(&self, id: String) -> Result<(), Error>;
}

pub trait AccountService {
    fn open(&self, owner: String) -> Result<Account, Error>;
}
"#;
        let types = parse(src);
        assert_eq!(types.len(), 4, "expected 2 structs and 2 traits");

        let user = types.iter().find(|t| t.name == "User").expect("User not found");
        let account = types.iter().find(|t| t.name == "Account").expect("Account not found");
        let user_repo = types
            .iter()
            .find(|t| t.name == "UserRepository")
            .expect("UserRepository not found");
        let account_svc = types
            .iter()
            .find(|t| t.name == "AccountService")
            .expect("AccountService not found");

        assert_eq!(user.kind, TypeDefKind::Struct);
        assert_eq!(user.fields.len(), 2);
        assert_eq!(user.fields[0], ("name".to_string(), "String".to_string()));
        assert_eq!(user.fields[1], ("email".to_string(), "String".to_string()));
        assert!(user.methods.is_empty());

        assert_eq!(account.kind, TypeDefKind::Struct);
        assert_eq!(account.fields.len(), 2);
        assert_eq!(account.fields[0], ("id".to_string(), "u64".to_string()));
        assert_eq!(
            account.fields[1],
            ("owner".to_string(), "String".to_string())
        );
        assert!(account.methods.is_empty());

        assert_eq!(user_repo.kind, TypeDefKind::Trait);
        assert!(user_repo.fields.is_empty());
        assert_eq!(user_repo.methods.len(), 2);
        assert_eq!(user_repo.methods[0].name, "create");
        assert_eq!(user_repo.methods[1].name, "delete");

        assert_eq!(account_svc.kind, TypeDefKind::Trait);
        assert!(account_svc.fields.is_empty());
        assert_eq!(account_svc.methods.len(), 1);
        assert_eq!(account_svc.methods[0].name, "open");
    }

    #[test]
    fn test_parse_imports_simple() {
        let src = r#"
use crate::domain::Order;
use crate::port::OrderRepository;

pub struct PlaceOrder;
"#;
        let imports = parse_imports(src);
        assert_eq!(imports, vec![
            "crate::domain::Order",
            "crate::port::OrderRepository",
        ]);
    }

    #[test]
    fn test_parse_imports_grouped() {
        let src = r#"
use crate::domain::{Order, Money};
use std::collections::HashMap;

pub struct Service;
"#;
        let imports = parse_imports(src);
        assert_eq!(imports, vec![
            "crate::domain::Order",
            "crate::domain::Money",
            "std::collections::HashMap",
        ]);
    }
}

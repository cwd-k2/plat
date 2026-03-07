use std::collections::HashMap;

use plat_manifest::{Language, Manifest};
use plat_contract::generate;

const GOLDEN: &str = include_str!("../../../test/golden/manifest.json");

fn manifest() -> Manifest {
    serde_json::from_str(GOLDEN).expect("golden manifest should parse")
}

fn empty_map() -> HashMap<String, String> {
    HashMap::new()
}

// ===========================================================================
// Go contract generation
// ===========================================================================

#[test]
fn go_contract_file_per_boundary() {
    let files = generate(&manifest(), Language::Go, &empty_map(), &empty_map());
    assert_eq!(files.len(), 2, "one contract per boundary");
}

#[test]
fn go_contract_structure() {
    let files = generate(&manifest(), Language::Go, &empty_map(), &empty_map());
    let (path, content) = files
        .iter()
        .find(|(p, _)| p.to_string_lossy().contains("order_repository"))
        .expect("should have OrderRepository contract");

    assert!(path.to_string_lossy().ends_with("_contract_test.go"));
    assert!(content.contains("package interface_test"));
    assert!(content.contains("import \"testing\""));
    assert!(content.contains("type OrderRepositoryContract struct {"));
    assert!(content.contains("func (c OrderRepositoryContract) TestSave(t *testing.T)"));
    assert!(content.contains("func (c OrderRepositoryContract) TestFindById(t *testing.T)"));
}

#[test]
fn go_contract_adapters_listed() {
    let files = generate(&manifest(), Language::Go, &empty_map(), &empty_map());
    let (_, content) = files
        .iter()
        .find(|(p, _)| p.to_string_lossy().contains("order_repository"))
        .unwrap();
    assert!(content.contains("Known adapters: PostgresOrderRepo"));
}

#[test]
fn go_contract_error_handling() {
    let files = generate(&manifest(), Language::Go, &empty_map(), &empty_map());
    let (_, content) = files
        .iter()
        .find(|(p, _)| p.to_string_lossy().contains("order_repository"))
        .unwrap();
    assert!(content.contains("err := adapter."));
    assert!(content.contains("if err != nil"));
}

#[test]
fn go_contract_zero_values() {
    let files = generate(&manifest(), Language::Go, &empty_map(), &empty_map());
    let (_, content) = files
        .iter()
        .find(|(p, _)| p.to_string_lossy().contains("payment_gateway"))
        .unwrap();
    // charge(amount Money, cardToken String) → zero values
    assert!(content.contains("\"\""), "String zero value should be empty string literal");
}

// ===========================================================================
// TypeScript contract generation
// ===========================================================================

#[test]
fn ts_contract_structure() {
    let files = generate(&manifest(), Language::TypeScript, &empty_map(), &empty_map());
    let (path, content) = files
        .iter()
        .find(|(p, _)| p.to_string_lossy().contains("order-repository"))
        .expect("should have OrderRepository contract");

    assert!(path.to_string_lossy().ends_with(".contract.ts"));
    assert!(content.contains("export function testOrderRepositoryContract("));
    assert!(content.contains("factory: () => OrderRepository"));
    assert!(content.contains("should implement save"));
    assert!(content.contains("should implement findById"));
}

#[test]
fn ts_contract_adapter_check() {
    let files = generate(&manifest(), Language::TypeScript, &empty_map(), &empty_map());
    let (_, content) = files
        .iter()
        .find(|(p, _)| p.to_string_lossy().contains("order-repository"))
        .unwrap();
    assert!(content.contains("typeof adapter.save !== \"function\""));
}

// ===========================================================================
// Rust contract generation
// ===========================================================================

#[test]
fn rust_contract_structure() {
    let files = generate(&manifest(), Language::Rust, &empty_map(), &empty_map());
    let (path, content) = files
        .iter()
        .find(|(p, _)| p.to_string_lossy().contains("order_repository"))
        .expect("should have OrderRepository contract");

    assert!(path.to_string_lossy().ends_with("_contract.rs"));
    assert!(content.contains("#[cfg(test)]"));
    assert!(content.contains("pub fn test_order_repository_contract(adapter: &mut impl OrderRepository)"));
    assert!(content.contains("adapter.save("));
    assert!(content.contains("adapter.find_by_id("));
}

#[test]
fn rust_contract_zero_values() {
    let files = generate(&manifest(), Language::Rust, &empty_map(), &empty_map());
    let (_, content) = files
        .iter()
        .find(|(p, _)| p.to_string_lossy().contains("payment_gateway"))
        .unwrap();
    assert!(content.contains("String::new()"), "String zero should be String::new()");
}

#[test]
fn rust_contract_known_adapters() {
    let files = generate(&manifest(), Language::Rust, &empty_map(), &empty_map());
    let (_, content) = files
        .iter()
        .find(|(p, _)| p.to_string_lossy().contains("order_repository"))
        .unwrap();
    assert!(content.contains("Known adapters: PostgresOrderRepo"));
}

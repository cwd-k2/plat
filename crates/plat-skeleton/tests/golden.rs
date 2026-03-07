use std::collections::HashMap;

use plat_manifest::{Language, Manifest};
use plat_skeleton::{generate, Config};

const GOLDEN: &str = include_str!("../../../test/golden/manifest.json");

fn manifest() -> Manifest {
    serde_json::from_str(GOLDEN).expect("golden manifest should parse")
}

fn config(lang: Language) -> Config {
    Config::new(lang, HashMap::new(), HashMap::new(), None)
}

fn find_file<'a>(files: &'a [(String, String)], suffix: &str) -> &'a str {
    files
        .iter()
        .find(|(p, _)| p.ends_with(suffix))
        .map(|(_, c)| c.as_str())
        .unwrap_or_else(|| panic!("no file ending with {suffix}"))
}

// ===========================================================================
// Go generation
// ===========================================================================

#[test]
fn go_model_struct() {
    let files = generate(&config(Language::Go), &manifest());
    let order = find_file(&files, "order.go");
    assert!(order.contains("package core"));
    assert!(order.contains("type Order struct {"));
    assert!(order.contains("\tId"));
    assert!(order.contains("\tCustomerId"));
    assert!(order.contains("\tItems"));
    assert!(order.contains("\tTotal"));
}

#[test]
fn go_boundary_interface() {
    let files = generate(&config(Language::Go), &manifest());
    let repo = find_file(&files, "order_repository.go");
    assert!(repo.contains("package interface"));
    assert!(repo.contains("type OrderRepository interface {"));
    assert!(repo.contains("Save("));
    assert!(repo.contains("FindById("));
    assert!(repo.contains("error"));
}

#[test]
fn go_operation_with_deps() {
    let files = generate(&config(Language::Go), &manifest());
    let po = find_file(&files, "place_order.go");
    assert!(po.contains("type PlaceOrder struct {"));
    assert!(po.contains("orderRepository interface.OrderRepository"));
    assert!(po.contains("paymentGateway interface.PaymentGateway"));
    assert!(po.contains("func NewPlaceOrder("));
    assert!(po.contains("func (uc *PlaceOrder) Execute("));
    assert!(po.contains("panic(\"TODO: implement PlaceOrder\")"));
}

#[test]
fn go_adapter_with_implements() {
    let files = generate(&config(Language::Go), &manifest());
    let pg = find_file(&files, "postgres_order_repo.go");
    assert!(pg.contains("package infra"));
    assert!(pg.contains("// implements OrderRepository"));
    assert!(pg.contains("type PostgresOrderRepo struct {"));
    assert!(pg.contains("\tDb"));
}

#[test]
fn go_file_count() {
    let files = generate(&config(Language::Go), &manifest());
    // 3 models + 2 boundaries + 3 operations + 3 adapters = 11 (Compose excluded)
    assert!(
        files.len() >= 10,
        "expected at least 10 Go files, got {}",
        files.len()
    );
}

// ===========================================================================
// TypeScript generation
// ===========================================================================

#[test]
fn ts_model_interface() {
    let files = generate(&config(Language::TypeScript), &manifest());
    let order = find_file(&files, "order.ts");
    assert!(order.contains("export interface Order {"));
    assert!(order.contains("  id: UUID;"));
    assert!(order.contains("  items: OrderItem[];"));
}

#[test]
fn ts_boundary_interface() {
    let files = generate(&config(Language::TypeScript), &manifest());
    let repo = find_file(&files, "order-repository.ts");
    assert!(repo.contains("export interface OrderRepository {"));
    assert!(repo.contains("save("));
    assert!(repo.contains("findById("));
    assert!(repo.contains("Promise<"));
}

#[test]
fn ts_operation_class() {
    let files = generate(&config(Language::TypeScript), &manifest());
    let po = find_file(&files, "place-order.ts");
    assert!(po.contains("export class PlaceOrder {"));
    assert!(po.contains("private orderRepository: OrderRepository"));
    assert!(po.contains("private paymentGateway: PaymentGateway"));
    assert!(po.contains("async execute("));
    assert!(po.contains("throw new Error(\"TODO: implement PlaceOrder\")"));
}

#[test]
fn ts_adapter_implements() {
    let files = generate(&config(Language::TypeScript), &manifest());
    let pg = find_file(&files, "postgres-order-repo.ts");
    assert!(pg.contains("export class PostgresOrderRepo implements OrderRepository {"));
    assert!(pg.contains("async save("));
    assert!(pg.contains("async findById("));
}

// ===========================================================================
// Rust generation
// ===========================================================================

#[test]
fn rust_model_struct() {
    let files = generate(&config(Language::Rust), &manifest());
    let order = find_file(&files, "order.rs");
    assert!(order.contains("#[derive(Debug, Clone)]"));
    assert!(order.contains("pub struct Order {"));
    assert!(order.contains("    pub id:"));
    assert!(order.contains("    pub items:"));
}

#[test]
fn rust_boundary_trait() {
    let files = generate(&config(Language::Rust), &manifest());
    let repo = find_file(&files, "order_repository.rs");
    assert!(repo.contains("pub trait OrderRepository {"));
    assert!(repo.contains("fn save("));
    assert!(repo.contains("fn find_by_id("));
    assert!(repo.contains("Result<"));
}

#[test]
fn rust_operation_fn() {
    let files = generate(&config(Language::Rust), &manifest());
    let po = find_file(&files, "place_order.rs");
    assert!(po.contains("pub fn execute("));
    assert!(po.contains("order_repository: &mut impl OrderRepository"));
    assert!(po.contains("payment_gateway: &mut impl PaymentGateway"));
    assert!(po.contains("todo!(\"implement PlaceOrder\")"));
}

#[test]
fn rust_adapter_impl() {
    let files = generate(&config(Language::Rust), &manifest());
    let pg = find_file(&files, "postgres_order_repo.rs");
    assert!(pg.contains("pub struct PostgresOrderRepo {"));
    assert!(pg.contains("impl OrderRepository for PostgresOrderRepo {"));
    assert!(pg.contains("fn save("));
    assert!(pg.contains("fn find_by_id("));
}

#[test]
fn rust_mod_rs_generated() {
    let files = generate(&config(Language::Rust), &manifest());
    let mods: Vec<_> = files.iter().filter(|(p, _)| p.ends_with("mod.rs")).collect();
    assert!(!mods.is_empty(), "should generate mod.rs files");
    let any_mod = &mods[0].1;
    assert!(any_mod.contains("pub mod"));
}

// ===========================================================================
// Layer-dir mapping
// ===========================================================================

#[test]
fn layer_dir_override() {
    let mut dirs = HashMap::new();
    dirs.insert("core".to_string(), "src/domain".to_string());
    dirs.insert("infra".to_string(), "src/infra".to_string());
    let cfg = Config::new(Language::Go, dirs, HashMap::new(), None);
    let files = generate(&cfg, &manifest());
    let order = files.iter().find(|(p, _)| p.contains("order.go")).unwrap();
    assert!(
        order.0.starts_with("src/domain"),
        "expected src/domain prefix, got {}",
        order.0
    );
}

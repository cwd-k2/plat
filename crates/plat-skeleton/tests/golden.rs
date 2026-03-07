use plat_manifest::{DeclKind, Manifest};

const GOLDEN: &str = include_str!("../../../test/golden/manifest.json");

fn manifest() -> Manifest {
    serde_json::from_str(GOLDEN).expect("golden manifest should parse")
}

#[test]
fn generates_go_model() {
    let m = manifest();
    let order = m.declarations.iter().find(|d| d.name == "Order").unwrap();
    assert_eq!(order.kind, DeclKind::Model);
    assert_eq!(order.fields.len(), 7);
    assert_eq!(order.fields[0].name, "id");
    assert_eq!(order.fields[0].typ, "UUID");
}

#[test]
fn generates_go_boundary() {
    let m = manifest();
    let repo = m.declarations.iter().find(|d| d.name == "OrderRepository").unwrap();
    assert_eq!(repo.kind, DeclKind::Boundary);
    assert_eq!(repo.ops.len(), 2);
    assert_eq!(repo.ops[0].name, "save");
}

#[test]
fn generates_go_operation() {
    let m = manifest();
    let po = m.declarations.iter().find(|d| d.name == "PlaceOrder").unwrap();
    assert_eq!(po.kind, DeclKind::Operation);
    assert_eq!(po.needs.len(), 2);
    assert_eq!(po.inputs.len(), 2);
}

#[test]
fn generates_go_adapter() {
    let m = manifest();
    let pg = m.declarations.iter().find(|d| d.name == "PostgresOrderRepo").unwrap();
    assert_eq!(pg.kind, DeclKind::Adapter);
    assert_eq!(pg.implements.as_deref(), Some("OrderRepository"));
    assert_eq!(pg.injects.len(), 1);
}

#[test]
fn custom_types_available() {
    let m = manifest();
    assert_eq!(m.custom_types, vec!["UUID"]);
}

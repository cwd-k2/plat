use plat_manifest::{DeclKind, Manifest};

const GOLDEN: &str = include_str!("../../../test/golden/manifest.json");

fn manifest() -> Manifest {
    serde_json::from_str(GOLDEN).expect("golden manifest should parse")
}

#[test]
fn has_boundaries_for_contracts() {
    let m = manifest();
    let boundaries: Vec<_> = m.declarations.iter()
        .filter(|d| d.kind == DeclKind::Boundary)
        .collect();
    assert_eq!(boundaries.len(), 2);
}

#[test]
fn boundary_ops_have_io() {
    let m = manifest();
    let repo = m.declarations.iter().find(|d| d.name == "OrderRepository").unwrap();
    for op in &repo.ops {
        assert!(!op.inputs.is_empty() || !op.outputs.is_empty(),
            "op {} should have inputs or outputs", op.name);
    }
}

#[test]
fn adapters_implement_boundaries() {
    let m = manifest();
    let adapters: Vec<_> = m.declarations.iter()
        .filter(|d| d.kind == DeclKind::Adapter && d.implements.is_some())
        .collect();
    assert_eq!(adapters.len(), 2, "PostgresOrderRepo and StripePayment implement boundaries");

    let boundary_names: Vec<_> = m.declarations.iter()
        .filter(|d| d.kind == DeclKind::Boundary)
        .map(|d| d.name.as_str())
        .collect();

    for adapter in &adapters {
        let impl_name = adapter.implements.as_ref().unwrap();
        assert!(boundary_names.contains(&impl_name.as_str()),
            "adapter {} implements unknown boundary {}", adapter.name, impl_name);
    }
}

#[test]
fn bindings_match_adapters() {
    let m = manifest();
    assert_eq!(m.bindings.len(), 2);
    assert_eq!(m.bindings[0].boundary, "OrderRepository");
    assert_eq!(m.bindings[0].adapter, "PostgresOrderRepo");
}

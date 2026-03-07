use plat_manifest::{Binding, DeclKind, Declaration, Field, Layer, Manifest};

const GOLDEN: &str = include_str!("../../../test/golden/manifest.json");

#[test]
fn parse_golden_manifest() {
    let m: Manifest = serde_json::from_str(GOLDEN).expect("golden manifest should parse");

    assert_eq!(m.schema_version, "0.6");
    assert_eq!(m.name, "order-service");
    assert_eq!(m.layers.len(), 4);
    assert_eq!(m.type_aliases.len(), 1);
    assert_eq!(m.type_aliases[0].name, "Money");
    assert_eq!(m.custom_types, vec!["UUID"]);
    assert_eq!(m.declarations.len(), 12);
    assert_eq!(m.bindings.len(), 2);
}

#[test]
fn golden_decl_kinds() {
    let m: Manifest = serde_json::from_str(GOLDEN).unwrap();

    let models: Vec<_> = m.declarations.iter().filter(|d| d.kind == DeclKind::Model).collect();
    let boundaries: Vec<_> = m.declarations.iter().filter(|d| d.kind == DeclKind::Boundary).collect();
    let operations: Vec<_> = m.declarations.iter().filter(|d| d.kind == DeclKind::Operation).collect();
    let adapters: Vec<_> = m.declarations.iter().filter(|d| d.kind == DeclKind::Adapter).collect();
    let composes: Vec<_> = m.declarations.iter().filter(|d| d.kind == DeclKind::Compose).collect();

    assert_eq!(models.len(), 3, "3 models: OrderStatus, OrderItem, Order");
    assert_eq!(boundaries.len(), 2, "2 boundaries: OrderRepository, PaymentGateway");
    assert_eq!(operations.len(), 3, "3 operations: PlaceOrder, CancelOrder, GetOrder");
    assert_eq!(adapters.len(), 3, "3 adapters: PostgresOrderRepo, StripePayment, OrderHttpHandler");
    assert_eq!(composes.len(), 1, "1 compose: AppRoot");
}

#[test]
fn golden_boundary_ops() {
    let m: Manifest = serde_json::from_str(GOLDEN).unwrap();
    let repo = m.declarations.iter().find(|d| d.name == "OrderRepository").unwrap();

    assert_eq!(repo.ops.len(), 2);
    assert_eq!(repo.ops[0].name, "save");
    assert_eq!(repo.ops[0].inputs.len(), 1);
    assert_eq!(repo.ops[0].inputs[0].name, "order");
    assert_eq!(repo.ops[0].inputs[0].typ, "Order");
}

#[test]
fn golden_operation_io() {
    let m: Manifest = serde_json::from_str(GOLDEN).unwrap();
    let po = m.declarations.iter().find(|d| d.name == "PlaceOrder").unwrap();

    assert_eq!(po.inputs.len(), 2);
    assert_eq!(po.outputs.len(), 2);
    assert_eq!(po.needs, vec!["OrderRepository", "PaymentGateway"]);
}

#[test]
fn golden_adapter_implements() {
    let m: Manifest = serde_json::from_str(GOLDEN).unwrap();
    let pg = m.declarations.iter().find(|d| d.name == "PostgresOrderRepo").unwrap();

    assert_eq!(pg.implements.as_deref(), Some("OrderRepository"));
    assert_eq!(pg.injects.len(), 1);
    assert_eq!(pg.injects[0].name, "db");
    assert_eq!(pg.injects[0].typ, "*sql.DB");
}

#[test]
fn golden_bindings() {
    let m: Manifest = serde_json::from_str(GOLDEN).unwrap();

    assert_eq!(m.bindings[0].boundary, "OrderRepository");
    assert_eq!(m.bindings[0].adapter, "PostgresOrderRepo");
    assert_eq!(m.bindings[1].boundary, "PaymentGateway");
    assert_eq!(m.bindings[1].adapter, "StripePayment");
}

#[test]
fn golden_roundtrip() {
    let m: Manifest = serde_json::from_str(GOLDEN).unwrap();
    let json = serde_json::to_string_pretty(&m).unwrap();
    let m2: Manifest = serde_json::from_str(&json).expect("roundtrip should work");

    assert_eq!(m2.name, m.name);
    assert_eq!(m2.schema_version, m.schema_version);
    assert_eq!(m2.declarations.len(), m.declarations.len());
    assert_eq!(m2.custom_types, m.custom_types);
}

fn multi_service_manifest() -> Manifest {
    let shared_model = Declaration {
        name: "Money".into(),
        kind: DeclKind::Model,
        layer: Some("domain".into()),
        service: None,
        fields: vec![Field { name: "amount".into(), typ: "Int".into() }],
        ..Default::default()
    };
    let order_model = Declaration {
        name: "Order".into(),
        kind: DeclKind::Model,
        layer: Some("domain".into()),
        service: Some("order".into()),
        fields: vec![Field { name: "total".into(), typ: "Money".into() }],
        ..Default::default()
    };
    let order_repo = Declaration {
        name: "OrderRepo".into(),
        kind: DeclKind::Boundary,
        layer: Some("port".into()),
        service: Some("order".into()),
        ..Default::default()
    };
    let pg_order = Declaration {
        name: "PgOrderRepo".into(),
        kind: DeclKind::Adapter,
        layer: Some("infra".into()),
        service: Some("order".into()),
        implements: Some("OrderRepo".into()),
        ..Default::default()
    };
    let payment_model = Declaration {
        name: "Payment".into(),
        kind: DeclKind::Model,
        layer: Some("domain".into()),
        service: Some("payment".into()),
        ..Default::default()
    };

    Manifest {
        schema_version: "0.6".into(),
        name: "platform".into(),
        layers: vec![
            Layer { name: "domain".into(), depends: vec![] },
            Layer { name: "port".into(), depends: vec!["domain".into()] },
            Layer { name: "infra".into(), depends: vec!["domain".into(), "port".into()] },
        ],
        declarations: vec![shared_model, order_model, order_repo, pg_order, payment_model],
        bindings: vec![Binding {
            boundary: "OrderRepo".into(),
            adapter: "PgOrderRepo".into(),
        }],
        ..Default::default()
    }
}

#[test]
fn split_by_service_count() {
    let m = multi_service_manifest();
    let parts = m.split_by_service();
    assert_eq!(parts.len(), 2, "order + payment");
}

#[test]
fn split_by_service_names() {
    let m = multi_service_manifest();
    let parts = m.split_by_service();
    assert_eq!(parts[0].name, "platform-order");
    assert_eq!(parts[1].name, "platform-payment");
}

#[test]
fn split_shared_included_in_all() {
    let m = multi_service_manifest();
    let parts = m.split_by_service();
    // Money (shared) should appear in both
    for part in &parts {
        assert!(
            part.declarations.iter().any(|d| d.name == "Money"),
            "shared Money missing from {}",
            part.name
        );
    }
}

#[test]
fn split_service_specific_decls() {
    let m = multi_service_manifest();
    let parts = m.split_by_service();
    let order = &parts[0];
    let payment = &parts[1];

    assert!(order.declarations.iter().any(|d| d.name == "Order"));
    assert!(order.declarations.iter().any(|d| d.name == "OrderRepo"));
    assert!(!order.declarations.iter().any(|d| d.name == "Payment"));

    assert!(payment.declarations.iter().any(|d| d.name == "Payment"));
    assert!(!payment.declarations.iter().any(|d| d.name == "Order"));
}

#[test]
fn split_bindings_filtered() {
    let m = multi_service_manifest();
    let parts = m.split_by_service();
    let order = &parts[0];
    let payment = &parts[1];

    assert_eq!(order.bindings.len(), 1, "OrderRepo binding in order service");
    assert_eq!(payment.bindings.len(), 0, "no bindings in payment service");
}

#[test]
fn split_empty_when_no_service() {
    let m: Manifest = serde_json::from_str(GOLDEN).unwrap();
    let parts = m.split_by_service();
    assert!(parts.is_empty(), "no service tags → empty split");
}

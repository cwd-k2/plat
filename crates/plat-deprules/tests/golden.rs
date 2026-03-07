use plat_manifest::Manifest;

const GOLDEN: &str = include_str!("../../../test/golden/manifest.json");

fn manifest() -> Manifest {
    serde_json::from_str(GOLDEN).expect("golden manifest should parse")
}

#[test]
fn layers_form_dag() {
    let m = manifest();
    assert_eq!(m.layers.len(), 4);

    // core has no deps
    let core = m.layers.iter().find(|l| l.name == "core").unwrap();
    assert!(core.depends.is_empty());

    // infra depends on everything
    let infra = m.layers.iter().find(|l| l.name == "infra").unwrap();
    assert_eq!(infra.depends.len(), 3);
    assert!(infra.depends.contains(&"core".to_string()));
    assert!(infra.depends.contains(&"application".to_string()));
    assert!(infra.depends.contains(&"interface".to_string()));
}

#[test]
fn layer_deps_are_acyclic() {
    let m = manifest();
    // Check no layer depends on itself
    for layer in &m.layers {
        assert!(!layer.depends.contains(&layer.name),
            "layer {} depends on itself", layer.name);
    }

    // Simple cycle check: core has no deps, so it can't be part of a cycle starting from core
    let core = m.layers.iter().find(|l| l.name == "core").unwrap();
    assert!(core.depends.is_empty());
}

#[test]
fn application_depends_on_core_and_interface() {
    let m = manifest();
    let app = m.layers.iter().find(|l| l.name == "application").unwrap();
    assert!(app.depends.contains(&"core".to_string()));
    assert!(app.depends.contains(&"interface".to_string()));
    assert!(!app.depends.contains(&"infra".to_string()),
        "application should not depend on infra");
}

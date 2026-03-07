use std::collections::BTreeMap;

use plat_manifest::Manifest;
use plat_deprules::{build_policy, render_depguard, render_eslint, render_matrix};

const GOLDEN: &str = include_str!("../../../test/golden/manifest.json");

fn manifest() -> Manifest {
    serde_json::from_str(GOLDEN).expect("golden manifest should parse")
}

// ===========================================================================
// Policy construction
// ===========================================================================

#[test]
fn policy_layers() {
    let m = manifest();
    let policy = build_policy(&m);
    assert_eq!(policy.layers.len(), 4);
    assert_eq!(policy.layers[0], "core");
}

#[test]
fn core_allows_nothing() {
    let policy = build_policy(&manifest());
    let allowed = policy.allowed.get("core").unwrap();
    assert!(allowed.is_empty(), "core should have no dependencies");
}

#[test]
fn core_forbids_all_others() {
    let policy = build_policy(&manifest());
    let forbidden = policy.forbidden.get("core").unwrap();
    assert_eq!(forbidden.len(), 3, "core forbids application, interface, infra");
    assert!(forbidden.contains("application"));
    assert!(forbidden.contains("interface"));
    assert!(forbidden.contains("infra"));
}

#[test]
fn application_allows_core_and_interface() {
    let policy = build_policy(&manifest());
    let allowed = policy.allowed.get("application").unwrap();
    assert!(allowed.contains("core"));
    assert!(allowed.contains("interface"));
    assert!(!allowed.contains("infra"));
}

#[test]
fn infra_allows_all() {
    let policy = build_policy(&manifest());
    let forbidden = policy.forbidden.get("infra").unwrap();
    assert!(forbidden.is_empty(), "infra should forbid nothing");
}

// ===========================================================================
// Matrix rendering
// ===========================================================================

#[test]
fn matrix_contains_header() {
    let policy = build_policy(&manifest());
    let output = render_matrix(&policy);
    assert!(output.contains("Layer dependency matrix"));
    assert!(output.contains("check = allowed"));
}

#[test]
fn matrix_contains_layers() {
    let policy = build_policy(&manifest());
    let output = render_matrix(&policy);
    assert!(output.contains("core"));
    assert!(output.contains("application"));
    assert!(output.contains("interface"));
    assert!(output.contains("infra"));
}

#[test]
fn matrix_self_is_dot() {
    let policy = build_policy(&manifest());
    let output = render_matrix(&policy);
    // Each row should have a '.' for self
    for line in output.lines() {
        if line.starts_with("core") || line.starts_with("application")
            || line.starts_with("interface") || line.starts_with("infra")
        {
            assert!(line.contains('.'), "row should have self-reference dot: {line}");
        }
    }
}

#[test]
fn matrix_check_and_x() {
    let policy = build_policy(&manifest());
    let output = render_matrix(&policy);
    // application allows core → "check" should appear in application row
    let app_line = output.lines().find(|l| l.starts_with("application")).unwrap();
    assert!(app_line.contains("check"), "application should have allowed deps");

    // core forbids everything → should have "x"
    let core_line = output.lines().find(|l| l.starts_with("core")).unwrap();
    assert!(core_line.contains('x'), "core should forbid other layers");
}

// ===========================================================================
// Depguard rendering
// ===========================================================================

#[test]
fn depguard_yaml_structure() {
    let policy = build_policy(&manifest());
    let output = render_depguard(&policy, "github.com/example/app", &BTreeMap::new());
    assert!(output.contains("linters-settings:"));
    assert!(output.contains("depguard:"));
    assert!(output.contains("rules:"));
}

#[test]
fn depguard_core_denies_others() {
    let policy = build_policy(&manifest());
    let output = render_depguard(&policy, "github.com/example/app", &BTreeMap::new());
    assert!(output.contains("- pkg: \"github.com/example/app/application\""));
    assert!(output.contains("layer core must not depend on application"));
}

#[test]
fn depguard_with_layer_dir_mapping() {
    let policy = build_policy(&manifest());
    let mut dirs = BTreeMap::new();
    dirs.insert("core".to_string(), "domain".to_string());
    let output = render_depguard(&policy, "github.com/ex/app", &dirs);
    assert!(output.contains("domain:"), "layer-dir should remap core→domain");
    assert!(output.contains("**/domain/**"));
}

// ===========================================================================
// ESLint rendering
// ===========================================================================

#[test]
fn eslint_json_structure() {
    let policy = build_policy(&manifest());
    let output = render_eslint(&policy, &BTreeMap::new());
    assert!(output.contains("\"rules\""));
    assert!(output.contains("\"boundaries/element-types\""));
    assert!(output.contains("\"default\": \"disallow\""));
}

#[test]
fn eslint_layer_rules() {
    let policy = build_policy(&manifest());
    let output = render_eslint(&policy, &BTreeMap::new());
    // application allows core + interface
    assert!(output.contains("\"from\": \"application\""));
    assert!(output.contains("\"core\""));
    assert!(output.contains("\"interface\""));
}

#[test]
fn eslint_with_dir_mapping() {
    let policy = build_policy(&manifest());
    let mut dirs = BTreeMap::new();
    dirs.insert("core".to_string(), "src/domain".to_string());
    let output = render_eslint(&policy, &dirs);
    assert!(output.contains("\"src/domain\""), "should use mapped directory");
}

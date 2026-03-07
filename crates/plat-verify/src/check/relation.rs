use crate::check::{find_type_by_name, Finding};
use crate::config::{Config, Language, Severity};
use crate::extract::{FileFacts, MethodDef, TypeDef, TypeDefKind};
use plat_manifest::{DeclKind, Manifest};

/// R0xx: Check relationship conformance (implements, bindings).
pub fn check(manifest: &Manifest, facts: &[FileFacts], config: &Config) -> Vec<Finding> {
    let mut findings = Vec::new();
    let lang = config.source.language;

    // R001/R003: adapter implements boundary
    for decl in &manifest.declarations {
        if decl.kind != DeclKind::Adapter {
            continue;
        }
        let Some(ref boundary_name) = decl.implements else {
            continue;
        };

        let adapter_src_name = config.convert_type_name(&decl.name);
        let boundary_src_name = config.convert_type_name(boundary_name);

        let adapter_td = find_type_by_name(facts, &adapter_src_name, Some(&decl.name), config);
        let boundary_td = find_type_by_name(facts, &boundary_src_name, Some(boundary_name), config);

        let (Some(adapter), Some(boundary)) = (adapter_td, boundary_td) else {
            continue;
        };

        check_adapter_boundary(adapter, boundary, &decl.name, boundary_name, lang, &mut findings);
    }

    // R002: binding conformance
    for binding in &manifest.bindings {
        let adapter_src_name = config.convert_type_name(&binding.adapter);
        let boundary_src_name = config.convert_type_name(&binding.boundary);

        let adapter_td = find_type_by_name(facts, &adapter_src_name, Some(&binding.adapter), config);
        let boundary_td = find_type_by_name(facts, &boundary_src_name, Some(&binding.boundary), config);

        let (Some(adapter), Some(boundary)) = (adapter_td, boundary_td) else {
            continue;
        };

        if !check_implements(adapter, boundary, lang) {
            findings.push(Finding {
                code: "R002".to_string(),
                severity: Severity::Warning,
                declaration: binding.adapter.clone(),
                message: format!(
                    "binding {} -> {} but adapter does not implement boundary",
                    binding.boundary, binding.adapter
                ),
                expected: None,
                source_file: Some(adapter.file.display().to_string()),
                source_line: None,
            });
        }
    }

    findings
}

/// Check adapter-boundary relationship, emitting R001 (missing methods) and R003 (signature mismatch).
fn check_adapter_boundary(
    adapter: &TypeDef,
    boundary: &TypeDef,
    adapter_name: &str,
    boundary_name: &str,
    lang: Language,
    findings: &mut Vec<Finding>,
) {
    let missing: Vec<&str> = boundary
        .methods
        .iter()
        .filter(|bm| !adapter.methods.iter().any(|am| am.name == bm.name))
        .map(|m| m.name.as_str())
        .collect();

    if !missing.is_empty() {
        findings.push(Finding {
            code: "R001".to_string(),
            severity: Severity::Error,
            declaration: adapter_name.to_string(),
            message: format!("{} does not implement {}", adapter_name, boundary_name),
            expected: Some(format!("missing methods: {}", missing.join(", "))),
            source_file: Some(adapter.file.display().to_string()),
            source_line: None,
        });
    }

    // R003: signature mismatch (Go structural subtyping)
    if lang == Language::Go {
        for bm in &boundary.methods {
            if let Some(am) = adapter.methods.iter().find(|m| m.name == bm.name) {
                let mismatches = compare_signatures(bm, am);
                for mismatch in mismatches {
                    findings.push(Finding {
                        code: "R003".to_string(),
                        severity: Severity::Warning,
                        declaration: adapter_name.to_string(),
                        message: format!(
                            "method \"{}\" signature mismatch: {}",
                            bm.name, mismatch
                        ),
                        expected: Some(format_signature(bm)),
                        source_file: Some(adapter.file.display().to_string()),
                        source_line: None,
                    });
                }
            }
        }
    }
}

/// Compare two method signatures. Returns a list of mismatch descriptions.
fn compare_signatures(boundary_method: &MethodDef, adapter_method: &MethodDef) -> Vec<String> {
    let mut mismatches = Vec::new();

    let bp = &boundary_method.params;
    let ap = &adapter_method.params;
    if bp.len() != ap.len() {
        mismatches.push(format!(
            "parameter count: expected {}, found {}",
            bp.len(),
            ap.len()
        ));
    } else {
        for (i, ((_, bt), (_, at))) in bp.iter().zip(ap.iter()).enumerate() {
            if !types_compatible(bt, at) {
                mismatches.push(format!(
                    "parameter {} type: expected {}, found {}",
                    i, bt, at
                ));
            }
        }
    }

    let br = &boundary_method.returns;
    let ar = &adapter_method.returns;
    if br.len() != ar.len() {
        mismatches.push(format!(
            "return count: expected {}, found {}",
            br.len(),
            ar.len()
        ));
    } else {
        for (i, (bt, at)) in br.iter().zip(ar.iter()).enumerate() {
            if !types_compatible(bt, at) {
                mismatches.push(format!(
                    "return {} type: expected {}, found {}",
                    i, bt, at
                ));
            }
        }
    }

    mismatches
}

/// Lenient type compatibility for Go: strips pointer prefix, compares base type.
fn types_compatible(expected: &str, actual: &str) -> bool {
    let e = expected.trim().trim_start_matches('*');
    let a = actual.trim().trim_start_matches('*');
    if e == a {
        return true;
    }
    // Package-qualified match: domain.Order matches Order
    if let Some(suffix) = a.rsplit('.').next() {
        if let Some(e_suffix) = e.rsplit('.').next() {
            return suffix == e_suffix;
        }
    }
    false
}

/// Format a method signature for display.
fn format_signature(m: &MethodDef) -> String {
    let params: Vec<String> = m.params.iter().map(|(n, t)| {
        if n.is_empty() { t.clone() } else { format!("{} {}", n, t) }
    }).collect();
    let returns = m.returns.join(", ");
    if returns.is_empty() {
        format!("{}({})", m.name, params.join(", "))
    } else if m.returns.len() == 1 {
        format!("{}({}) {}", m.name, params.join(", "), returns)
    } else {
        format!("{}({}) ({})", m.name, params.join(", "), returns)
    }
}

/// Check whether an adapter type implements a boundary type (name-level).
fn check_implements(adapter: &TypeDef, boundary: &TypeDef, lang: Language) -> bool {
    match lang {
        Language::Go => {
            boundary
                .methods
                .iter()
                .all(|bm| adapter.methods.iter().any(|am| am.name == bm.name))
        }
        Language::TypeScript => {
            adapter.implements.iter().any(|i| i == &boundary.name)
        }
        Language::Rust => {
            if adapter.kind == TypeDefKind::Struct
                && boundary.kind == TypeDefKind::Trait
            {
                adapter.implements.iter().any(|i| i == &boundary.name)
            } else {
                false
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn method(name: &str, params: Vec<(&str, &str)>, returns: Vec<&str>) -> MethodDef {
        MethodDef {
            name: name.to_string(),
            params: params.into_iter().map(|(n, t)| (n.to_string(), t.to_string())).collect(),
            returns: returns.into_iter().map(|s| s.to_string()).collect(),
        }
    }

    fn make_type(name: &str, kind: TypeDefKind, methods: Vec<MethodDef>) -> TypeDef {
        TypeDef {
            name: name.to_string(),
            kind,
            file: PathBuf::from("test.go"),
            fields: vec![],
            methods,
            implements: vec![],
        }
    }

    #[test]
    fn r003_param_count_mismatch() {
        let boundary = make_type("Repo", TypeDefKind::Interface, vec![
            method("Save", vec![("order", "Order")], vec!["error"]),
        ]);
        let adapter = make_type("PgRepo", TypeDefKind::Struct, vec![
            method("Save", vec![("order", "Order"), ("ctx", "context.Context")], vec!["error"]),
        ]);
        let mut findings = Vec::new();
        check_adapter_boundary(&adapter, &boundary, "PgRepo", "Repo", Language::Go, &mut findings);
        let r003: Vec<_> = findings.iter().filter(|f| f.code == "R003").collect();
        assert_eq!(r003.len(), 1);
        assert!(r003[0].message.contains("parameter count"));
    }

    #[test]
    fn r003_return_type_mismatch() {
        let boundary = make_type("Repo", TypeDefKind::Interface, vec![
            method("FindByID", vec![("id", "string")], vec!["Order", "error"]),
        ]);
        let adapter = make_type("PgRepo", TypeDefKind::Struct, vec![
            method("FindByID", vec![("id", "string")], vec!["*Order", "error"]),
        ]);
        let mut findings = Vec::new();
        check_adapter_boundary(&adapter, &boundary, "PgRepo", "Repo", Language::Go, &mut findings);
        // *Order should match Order (pointer stripping)
        let r003: Vec<_> = findings.iter().filter(|f| f.code == "R003").collect();
        assert!(r003.is_empty(), "pointer types should be compatible");
    }

    #[test]
    fn r003_param_type_mismatch() {
        let boundary = make_type("Repo", TypeDefKind::Interface, vec![
            method("Save", vec![("order", "Order")], vec!["error"]),
        ]);
        let adapter = make_type("PgRepo", TypeDefKind::Struct, vec![
            method("Save", vec![("order", "Item")], vec!["error"]),
        ]);
        let mut findings = Vec::new();
        check_adapter_boundary(&adapter, &boundary, "PgRepo", "Repo", Language::Go, &mut findings);
        let r003: Vec<_> = findings.iter().filter(|f| f.code == "R003").collect();
        assert_eq!(r003.len(), 1);
        assert!(r003[0].message.contains("parameter 0 type"));
    }

    #[test]
    fn r003_package_qualified_compatible() {
        let boundary = make_type("Repo", TypeDefKind::Interface, vec![
            method("Save", vec![("order", "Order")], vec!["error"]),
        ]);
        let adapter = make_type("PgRepo", TypeDefKind::Struct, vec![
            method("Save", vec![("order", "domain.Order")], vec!["error"]),
        ]);
        let mut findings = Vec::new();
        check_adapter_boundary(&adapter, &boundary, "PgRepo", "Repo", Language::Go, &mut findings);
        let r003: Vec<_> = findings.iter().filter(|f| f.code == "R003").collect();
        assert!(r003.is_empty(), "package-qualified types should be compatible");
    }

    #[test]
    fn r001_missing_method() {
        let boundary = make_type("Repo", TypeDefKind::Interface, vec![
            method("Save", vec![], vec!["error"]),
            method("Delete", vec![], vec!["error"]),
        ]);
        let adapter = make_type("PgRepo", TypeDefKind::Struct, vec![
            method("Save", vec![], vec!["error"]),
        ]);
        let mut findings = Vec::new();
        check_adapter_boundary(&adapter, &boundary, "PgRepo", "Repo", Language::Go, &mut findings);
        let r001: Vec<_> = findings.iter().filter(|f| f.code == "R001").collect();
        assert_eq!(r001.len(), 1);
        assert!(r001[0].expected.as_ref().unwrap().contains("Delete"));
    }

    #[test]
    fn full_match_no_findings() {
        let boundary = make_type("Repo", TypeDefKind::Interface, vec![
            method("Save", vec![("order", "Order")], vec!["error"]),
            method("FindByID", vec![("id", "string")], vec!["Order", "error"]),
        ]);
        let adapter = make_type("PgRepo", TypeDefKind::Struct, vec![
            method("Save", vec![("order", "*domain.Order")], vec!["error"]),
            method("FindByID", vec![("id", "string")], vec!["*domain.Order", "error"]),
        ]);
        let mut findings = Vec::new();
        check_adapter_boundary(&adapter, &boundary, "PgRepo", "Repo", Language::Go, &mut findings);
        assert!(findings.is_empty(), "fully matching adapter should have no findings");
    }
}

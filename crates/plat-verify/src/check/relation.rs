use crate::check::{find_type_by_name, Finding};
use crate::config::{Config, Language, Severity};
use crate::extract::{FileFacts, TypeDef, TypeDefKind};
use plat_manifest::{DeclKind, Manifest};

/// R0xx: Check relationship conformance (implements, bindings).
pub fn check(manifest: &Manifest, facts: &[FileFacts], config: &Config) -> Vec<Finding> {
    let mut findings = Vec::new();
    let lang = config.source.language;

    // R001: adapter implements boundary
    for decl in &manifest.declarations {
        if decl.kind != DeclKind::Adapter {
            continue;
        }
        let Some(ref boundary_name) = decl.implements else {
            continue;
        };

        let adapter_src_name = config.convert_type_name(&decl.name);
        let boundary_src_name = config.convert_type_name(boundary_name);

        let adapter_td = find_type_by_name(facts, &adapter_src_name, config);
        let boundary_td = find_type_by_name(facts, &boundary_src_name, config);

        let (Some(adapter), Some(boundary)) = (adapter_td, boundary_td) else {
            continue; // existence checks handle missing types
        };

        if !check_implements(adapter, boundary, lang) {
            let missing: Vec<String> = boundary
                .methods
                .iter()
                .filter(|bm| !adapter.methods.iter().any(|am| am.name == bm.name))
                .map(|m| m.name.clone())
                .collect();

            findings.push(Finding {
                code: "R001".to_string(),
                severity: Severity::Error,
                declaration: decl.name.clone(),
                message: format!(
                    "{} does not implement {}",
                    decl.name, boundary_name
                ),
                expected: if missing.is_empty() {
                    None
                } else {
                    Some(format!("missing methods: {}", missing.join(", ")))
                },
                source_file: Some(adapter.file.display().to_string()),
                source_line: None,
            });
        }
    }

    // R002: binding conformance
    for binding in &manifest.bindings {
        let adapter_src_name = config.convert_type_name(&binding.adapter);
        let boundary_src_name = config.convert_type_name(&binding.boundary);

        let adapter_td = find_type_by_name(facts, &adapter_src_name, config);
        let boundary_td = find_type_by_name(facts, &boundary_src_name, config);

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

/// Check whether an adapter type implements a boundary type.
fn check_implements(adapter: &TypeDef, boundary: &TypeDef, lang: Language) -> bool {
    match lang {
        Language::Go => {
            // Go: duck typing — adapter must have all boundary methods
            boundary
                .methods
                .iter()
                .all(|bm| adapter.methods.iter().any(|am| am.name == bm.name))
        }
        Language::TypeScript => {
            // TS: explicit implements clause
            adapter.implements.iter().any(|i| i == &boundary.name)
        }
        Language::Rust => {
            // Rust: explicit impl Trait for Struct
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

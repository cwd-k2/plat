use crate::check::Finding;
use crate::config::{Config, Language, Severity};
use crate::extract::{FileFacts, TypeDef, TypeDefKind};
use plat_manifest::{DeclKind, Manifest};
use plat_manifest::naming;

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

        let adapter_src_name = naming::convert(&decl.name, config.type_case());
        let boundary_src_name = naming::convert(boundary_name, config.type_case());

        let adapter_td = find_type(facts, &adapter_src_name);
        let boundary_td = find_type(facts, &boundary_src_name);

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
        let adapter_src_name = naming::convert(&binding.adapter, config.type_case());
        let boundary_src_name = naming::convert(&binding.boundary, config.type_case());

        let adapter_td = find_type(facts, &adapter_src_name);
        let boundary_td = find_type(facts, &boundary_src_name);

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

fn find_type<'a>(facts: &'a [FileFacts], name: &str) -> Option<&'a TypeDef> {
    facts
        .iter()
        .flat_map(|f| &f.types)
        .find(|td| td.name == name)
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

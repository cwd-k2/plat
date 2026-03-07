use crate::check::Finding;
use crate::config::{Config, Severity};
use crate::extract::{FileFacts, TypeDefKind};
use plat_manifest::{DeclKind, Manifest};
use plat_manifest::naming;

/// E0xx: Check that each manifest declaration has a corresponding source type.
pub fn check(manifest: &Manifest, facts: &[FileFacts], config: &Config) -> Vec<Finding> {
    let mut findings = Vec::new();

    for decl in &manifest.declarations {
        let (code, severity, expected_kind) = match decl.kind {
            DeclKind::Model => ("E001", Severity::Error, Some(TypeDefKind::Struct)),
            DeclKind::Boundary => ("E002", Severity::Error, Some(TypeDefKind::Interface)),
            DeclKind::Adapter => ("E003", Severity::Error, Some(TypeDefKind::Struct)),
            DeclKind::Operation => ("E004", Severity::Warning, None),
            DeclKind::Compose | DeclKind::Unknown => continue,
        };

        let expected_name = naming::convert(&decl.name, config.type_case());
        let found = find_type(facts, &expected_name, &decl.layer, expected_kind);

        if found.is_none() {
            let layer_hint = decl
                .layer
                .as_ref()
                .and_then(|l| config.source.layer_dirs.get(l))
                .map(|d| format!(" in {d}/"))
                .unwrap_or_default();

            findings.push(Finding {
                code: code.to_string(),
                severity,
                declaration: decl.name.clone(),
                message: format!("{} {} not found", decl.kind, decl.name),
                expected: Some(format!(
                    "{kind}{layer_hint}",
                    kind = match decl.kind {
                        DeclKind::Model | DeclKind::Adapter => "struct",
                        DeclKind::Boundary => "interface/trait",
                        DeclKind::Operation => "struct/function",
                        DeclKind::Compose | DeclKind::Unknown => unreachable!(),
                    },
                )),
                source_file: None,
                source_line: None,
            });
        }
    }

    findings
}

/// Search for a type in extracted facts.
fn find_type<'a>(
    facts: &'a [FileFacts],
    name: &str,
    layer: &Option<String>,
    _expected_kind: Option<TypeDefKind>,
) -> Option<&'a crate::extract::TypeDef> {
    for file in facts {
        // If declaration has a layer, prefer matching files in that layer
        if let Some(ref decl_layer) = layer {
            if let Some(ref file_layer) = file.layer {
                if decl_layer != file_layer {
                    continue;
                }
            }
        }
        for td in &file.types {
            if td.name == name {
                return Some(td);
            }
        }
    }
    // Fallback: search without layer constraint
    if layer.is_some() {
        for file in facts {
            for td in &file.types {
                if td.name == name {
                    return Some(td);
                }
            }
        }
    }
    None
}

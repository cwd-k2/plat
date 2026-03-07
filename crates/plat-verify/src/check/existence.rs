use crate::check::{find_type_by_name, Finding};
use crate::config::{Config, Severity};
use crate::extract::{FileFacts, TypeDefKind};
use plat_manifest::{DeclKind, Manifest};

/// E0xx: Check that each manifest declaration has a corresponding source type.
pub fn check(manifest: &Manifest, facts: &[FileFacts], config: &Config) -> Vec<Finding> {
    let mut findings = Vec::new();

    for decl in &manifest.declarations {
        let (code, severity, _expected_kind) = match decl.kind {
            DeclKind::Model => ("E001", Severity::Error, Some(TypeDefKind::Struct)),
            DeclKind::Boundary => ("E002", Severity::Error, Some(TypeDefKind::Interface)),
            DeclKind::Adapter => ("E003", Severity::Error, Some(TypeDefKind::Struct)),
            DeclKind::Operation => ("E004", Severity::Warning, None),
            DeclKind::Compose | DeclKind::Unknown => continue,
        };

        let expected_name = config.convert_type_name(&decl.name);
        let found = find_type_by_name(facts, &expected_name, Some(&decl.name), config);

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

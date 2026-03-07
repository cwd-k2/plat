use std::collections::HashSet;

use crate::check::Finding;
use crate::config::Severity;
use crate::manifest::{DeclKind, Manifest};

/// R003/R004: Check compose/binding consistency against manifest declarations.
pub fn check(manifest: &Manifest) -> Vec<Finding> {
    let mut findings = Vec::new();

    let decl_names: HashSet<(&str, DeclKind)> = manifest
        .declarations
        .iter()
        .map(|d| (d.name.as_str(), d.kind))
        .collect();

    // R003: binding references must exist with correct kinds
    for binding in &manifest.bindings {
        let boundary_ok = decl_names.contains(&(binding.boundary.as_str(), DeclKind::Boundary));
        let adapter_ok = decl_names.contains(&(binding.adapter.as_str(), DeclKind::Adapter));

        if !boundary_ok {
            findings.push(Finding {
                code: "R003".to_string(),
                severity: Severity::Error,
                declaration: binding.boundary.clone(),
                message: format!(
                    "binding references \"{}\" but no boundary with that name exists",
                    binding.boundary
                ),
                expected: Some("boundary declaration".to_string()),
                source_file: None,
                source_line: None,
            });
        }
        if !adapter_ok {
            findings.push(Finding {
                code: "R003".to_string(),
                severity: Severity::Error,
                declaration: binding.adapter.clone(),
                message: format!(
                    "binding references \"{}\" but no adapter with that name exists",
                    binding.adapter
                ),
                expected: Some("adapter declaration".to_string()),
                source_file: None,
                source_line: None,
            });
        }
    }

    // R004: boundary with no binding
    let bound_boundaries: HashSet<&str> = manifest
        .bindings
        .iter()
        .map(|b| b.boundary.as_str())
        .collect();

    for decl in &manifest.declarations {
        if decl.kind == DeclKind::Boundary && !bound_boundaries.contains(decl.name.as_str()) {
            findings.push(Finding {
                code: "R004".to_string(),
                severity: Severity::Warning,
                declaration: decl.name.clone(),
                message: "boundary has no binding".to_string(),
                expected: None,
                source_file: None,
                source_line: None,
            });
        }
    }

    findings
}

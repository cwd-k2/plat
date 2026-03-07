pub mod compose;
pub mod drift;
pub mod existence;
pub mod import_graph;
pub mod layer_deps;
pub mod structure;
pub mod relation;

use crate::config::{Config, Severity};
use crate::extract::FileFacts;
use plat_manifest::Manifest;

/// A single conformance finding.
#[derive(Debug, Clone)]
pub struct Finding {
    pub code: String,
    pub severity: Severity,
    pub declaration: String,
    pub message: String,
    pub expected: Option<String>,
    pub source_file: Option<String>,
    pub source_line: Option<usize>,
}

/// Summary statistics.
#[derive(Debug, Default)]
pub struct Summary {
    pub errors: usize,
    pub warnings: usize,
    pub info: usize,
    pub decls_checked: usize,
    pub decls_ok: usize,
}

impl Summary {
    pub fn from_findings(findings: &[Finding], decls_total: usize) -> Self {
        let mut errors = 0;
        let mut warnings = 0;
        let mut info = 0;
        let mut decl_issues = std::collections::HashSet::new();
        for f in findings {
            match f.severity {
                Severity::Error => errors += 1,
                Severity::Warning => warnings += 1,
                Severity::Info => info += 1,
            }
            decl_issues.insert(&f.declaration);
        }
        Self {
            errors,
            warnings,
            info,
            decls_checked: decls_total,
            decls_ok: decls_total.saturating_sub(decl_issues.len()),
        }
    }
}

/// Run all enabled checks.
pub fn run_checks(
    manifest: &Manifest,
    facts: &[FileFacts],
    config: &Config,
) -> Vec<Finding> {
    let mut findings = Vec::new();

    if config.checks.existence {
        findings.extend(existence::check(manifest, facts, config));
    }
    if config.checks.structure {
        findings.extend(structure::check(manifest, facts, config));
    }
    if config.checks.relation {
        findings.extend(relation::check(manifest, facts, config));
    }

    // Compose checks are always run (manifest-internal consistency)
    findings.extend(compose::check(manifest));

    if config.checks.layer_deps {
        findings.extend(layer_deps::check(manifest));
    }
    if config.checks.drift {
        findings.extend(drift::check(manifest, facts, config));
    }
    if config.checks.imports {
        findings.extend(import_graph::check(manifest, facts, config));
    }

    // Apply severity overrides
    for f in &mut findings {
        if let Some(sev) = config.severity_for(&f.code) {
            f.severity = sev;
        }
    }

    findings
}

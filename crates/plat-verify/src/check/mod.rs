pub mod compose;
pub mod drift;
pub mod existence;
pub mod import_graph;
pub mod layer_deps;
pub mod naming;
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

/// Summary statistics with convergence tracking (Reflexion Model).
#[derive(Debug, Default)]
pub struct Summary {
    pub errors: usize,
    pub warnings: usize,
    pub info: usize,
    pub decls_checked: usize,
    pub decls_ok: usize,
    /// Convergence counts (manifest elements confirmed in source).
    pub convergence: Convergence,
}

/// Convergence counters — confirmed alignments between manifest and source.
#[derive(Debug, Default, Clone)]
pub struct Convergence {
    pub types_expected: usize,
    pub types_found: usize,
    pub fields_expected: usize,
    pub fields_found: usize,
    pub methods_expected: usize,
    pub methods_found: usize,
}

impl Convergence {
    /// Architecture health score: ratio of confirmed elements to total expected.
    pub fn health_score(&self) -> f64 {
        let total = self.types_expected + self.fields_expected + self.methods_expected;
        if total == 0 {
            return 1.0;
        }
        let found = self.types_found + self.fields_found + self.methods_found;
        found as f64 / total as f64
    }
}

impl Summary {
    pub fn from_findings(findings: &[Finding], decls_total: usize, convergence: Convergence) -> Self {
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
            convergence,
        }
    }
}

/// Compute convergence counters by scanning manifest against extracted facts.
pub fn compute_convergence(
    manifest: &Manifest,
    facts: &[FileFacts],
    config: &Config,
) -> Convergence {
    use plat_manifest::DeclKind;

    let mut conv = Convergence::default();

    for decl in &manifest.declarations {
        match decl.kind {
            DeclKind::Compose | DeclKind::Unknown => continue,
            _ => {}
        }

        conv.types_expected += 1;

        let expected_name = plat_manifest::naming::convert(&decl.name, config.type_case());
        let td = facts
            .iter()
            .flat_map(|f| &f.types)
            .find(|t| t.name == expected_name);

        if let Some(td) = td {
            conv.types_found += 1;

            // Field convergence (Model / Adapter)
            for field in &decl.fields {
                conv.fields_expected += 1;
                let src_name = plat_manifest::naming::convert(&field.name, config.field_case());
                if td.fields.iter().any(|(n, _)| *n == src_name) {
                    conv.fields_found += 1;
                }
            }

            // Method convergence (Boundary)
            for op in &decl.ops {
                conv.methods_expected += 1;
                let src_name = plat_manifest::naming::convert(&op.name, config.method_case());
                if td.methods.iter().any(|m| m.name == src_name) {
                    conv.methods_found += 1;
                }
            }

            // Inject convergence (Adapter)
            for inject in &decl.injects {
                conv.fields_expected += 1;
                let src_name = plat_manifest::naming::convert(&inject.name, config.field_case());
                if td.fields.iter().any(|(n, _)| *n == src_name) {
                    conv.fields_found += 1;
                }
            }
        }
    }

    conv
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
    if config.checks.naming {
        findings.extend(naming::check(facts, config));
    }

    // Apply severity overrides
    for f in &mut findings {
        if let Some(sev) = config.severity_for(&f.code) {
            f.severity = sev;
        }
    }

    findings
}

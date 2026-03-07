pub mod compose;
pub mod drift;
pub mod existence;
pub mod import_graph;
pub mod layer_deps;
pub mod naming;
pub mod structure;
pub mod relation;

use crate::config::{Config, Language, Severity};
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
///
/// Each element has three states:
/// - Full match (1.0): name and type/signature match
/// - Partial match (0.5): name matches but type/signature differs
/// - Missing (0.0): not found at all
#[derive(Debug, Default, Clone)]
pub struct Convergence {
    pub types_expected: usize,
    pub types_found: usize,
    pub fields_expected: usize,
    pub fields_found: usize,
    pub fields_partial: usize,
    pub methods_expected: usize,
    pub methods_found: usize,
    pub methods_partial: usize,
}

impl Convergence {
    /// Architecture health score: weighted ratio of confirmed elements.
    ///
    /// Full matches count 1.0, partial matches count 0.5.
    pub fn health_score(&self) -> f64 {
        let total = self.types_expected + self.fields_expected + self.methods_expected;
        if total == 0 {
            return 1.0;
        }
        let score = self.types_found as f64
            + self.fields_found as f64
            + self.fields_partial as f64 * 0.5
            + self.methods_found as f64
            + self.methods_partial as f64 * 0.5;
        score / total as f64
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

        let expected_name = config.convert_type_name(&decl.name);
        let td = find_type_by_name(facts, &expected_name, config);

        if let Some(td) = td {
            conv.types_found += 1;

            let default_map = plat_manifest::typemap::defaults(config.source.language);

            // Field convergence (Model / Adapter)
            for field in &decl.fields {
                conv.fields_expected += 1;
                let src_name = config.convert_field_name(&field.name);
                if let Some((_, src_type)) = td.fields.iter().find(|(n, _)| *n == src_name) {
                    let expected_type = plat_manifest::typemap::resolve(
                        &field.typ, config.source.language, &default_map, &config.types,
                    );
                    if normalize_type(src_type) == normalize_type(&expected_type) {
                        conv.fields_found += 1;
                    } else {
                        conv.fields_partial += 1; // name match, type mismatch
                    }
                }
            }

            // Method convergence (Boundary)
            for op in &decl.ops {
                conv.methods_expected += 1;
                let src_name = config.convert_method_name(&op.name);
                if let Some(method) = td.methods.iter().find(|m| m.name == src_name) {
                    // Check parameter count as a proxy for signature match
                    let manifest_params = op.inputs.iter()
                        .filter(|p| !plat_manifest::typemap::is_error_type(&p.typ))
                        .count();
                    if manifest_params == method.params.len() {
                        conv.methods_found += 1;
                    } else {
                        conv.methods_partial += 1;
                    }
                }
            }

            // Inject convergence (Adapter): try name match or type match
            for inject in &decl.injects {
                conv.fields_expected += 1;
                let src_name = config.convert_field_name(&inject.name);
                let camel = plat_manifest::naming::convert(&inject.name, plat_manifest::Case::Camel);
                let resolved_type = plat_manifest::typemap::resolve(
                    &inject.typ, config.source.language, &default_map, &config.types,
                );
                if td.fields.iter().any(|(n, t)| {
                    *n == src_name || *n == inject.name || *n == camel
                        || normalize_type(t) == normalize_type(&resolved_type)
                }) {
                    conv.fields_found += 1;
                }
            }
        }
    }

    conv
}

/// Normalize a type string for comparison: strip pointer, package qualifier.
pub(crate) fn normalize_type(t: &str) -> String {
    let t = t.trim().trim_start_matches('*');
    if let Some(pos) = t.rfind('.') {
        let before = &t[..pos];
        if !before.contains('[') && !before.contains('<') {
            return t[pos + 1..].to_string();
        }
    }
    t.to_string()
}

/// Find a type by name across all facts, with Go package-prefix fallback.
///
/// In Go, `PostgresOrderRepo` may exist as `OrderRepo` in package `postgres`.
/// When exact match fails, tries suffix-matching against the expected name.
pub fn find_type_by_name<'a>(
    facts: &'a [FileFacts],
    expected_name: &str,
    config: &Config,
) -> Option<&'a crate::extract::TypeDef> {
    // Exact match
    for file in facts {
        for td in &file.types {
            if td.name == expected_name {
                return Some(td);
            }
        }
    }
    // Go package-prefix fallback: expected "PostgresOrderRepo", source has "OrderRepo"
    if config.source.language == Language::Go {
        for file in facts {
            for td in &file.types {
                if expected_name.ends_with(&td.name) && expected_name != td.name {
                    return Some(td);
                }
            }
        }
    }
    None
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

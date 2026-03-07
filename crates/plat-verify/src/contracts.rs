//! P2: Contract verification — compare manifests without source code.
//!
//! Given two manifests (consumer and provider), verify that:
//! - Consumer's `needs` references exist as boundaries in provider
//! - Provider's boundary ops are a superset of what consumer expects (structural subtyping)
//!
//! This enables multi-repo verification where services are defined in separate repos
//! and each publishes its manifest as an artifact.

use crate::check::Finding;
use crate::config::Severity;
use plat_manifest::{DeclKind, Manifest};

use std::collections::{HashMap, HashSet};

/// Contract finding codes:
/// - CT001: Consumer needs a boundary not found in provider
/// - CT002: Provider boundary is missing an op that consumer expects
/// - CT003: Provider op has different parameter count than consumer expects

/// Verify contract compatibility between a consumer and provider manifest.
pub fn check(consumer: &Manifest, provider: &Manifest) -> Vec<Finding> {
    let mut findings = Vec::new();

    // Build provider boundary map: name → declaration
    let provider_boundaries: HashMap<&str, &plat_manifest::Declaration> = provider
        .declarations
        .iter()
        .filter(|d| d.kind == DeclKind::Boundary)
        .map(|d| (d.name.as_str(), d))
        .collect();

    // Build set of all provider declaration names (for needs resolution)
    let provider_names: HashSet<&str> = provider
        .declarations
        .iter()
        .map(|d| d.name.as_str())
        .collect();

    // Check consumer needs against provider
    for decl in &consumer.declarations {
        for need in &decl.needs {
            // Only check cross-manifest needs (not local boundaries)
            let consumer_has = consumer
                .declarations
                .iter()
                .any(|d| d.name == *need);
            if consumer_has {
                continue;
            }

            if !provider_names.contains(need.as_str()) {
                findings.push(Finding {
                    code: "CT001".to_string(),
                    severity: Severity::Error,
                    declaration: decl.name.clone(),
                    message: format!(
                        "{} needs boundary \"{}\" which is not found in provider manifest \"{}\"",
                        decl.name, need, provider.name
                    ),
                    expected: Some(need.clone()),
                    source_file: None,
                    source_line: None,
                });
            }
        }
    }

    // Check boundary structural subtyping:
    // For shared boundaries (same name in both), provider ops must be superset of consumer ops
    let consumer_boundaries: HashMap<&str, &plat_manifest::Declaration> = consumer
        .declarations
        .iter()
        .filter(|d| d.kind == DeclKind::Boundary)
        .map(|d| (d.name.as_str(), d))
        .collect();

    for (name, consumer_bnd) in &consumer_boundaries {
        if let Some(provider_bnd) = provider_boundaries.get(name) {
            let provider_ops: HashMap<&str, &plat_manifest::Op> = provider_bnd
                .ops
                .iter()
                .map(|o| (o.name.as_str(), o))
                .collect();

            for consumer_op in &consumer_bnd.ops {
                match provider_ops.get(consumer_op.name.as_str()) {
                    None => {
                        findings.push(Finding {
                            code: "CT002".to_string(),
                            severity: Severity::Error,
                            declaration: name.to_string(),
                            message: format!(
                                "boundary \"{}\" op \"{}\" expected by consumer but not found in provider",
                                name, consumer_op.name
                            ),
                            expected: Some(consumer_op.name.clone()),
                            source_file: None,
                            source_line: None,
                        });
                    }
                    Some(provider_op) => {
                        // Check parameter count compatibility
                        if consumer_op.inputs.len() != provider_op.inputs.len() {
                            findings.push(Finding {
                                code: "CT003".to_string(),
                                severity: Severity::Warning,
                                declaration: name.to_string(),
                                message: format!(
                                    "boundary \"{}\" op \"{}\" has {} inputs in consumer but {} in provider",
                                    name, consumer_op.name,
                                    consumer_op.inputs.len(),
                                    provider_op.inputs.len()
                                ),
                                expected: None,
                                source_file: None,
                                source_line: None,
                            });
                        }
                    }
                }
            }
        }
    }

    findings
}

/// Render contract findings as text.
pub fn render_text(findings: &[Finding], consumer_name: &str, provider_name: &str) -> String {
    let mut out = String::new();
    out.push_str(&format!(
        "plat-verify contracts: {} ← {}\n",
        consumer_name, provider_name
    ));

    if findings.is_empty() {
        out.push_str("\nContracts compatible.\n");
    } else {
        out.push('\n');
        for f in findings {
            let sev = match f.severity {
                Severity::Error => "ERROR",
                Severity::Warning => "WARN ",
                Severity::Info => "INFO ",
            };
            out.push_str(&format!("[{}] {sev} {}\n", f.code, f.message));
        }
        out.push('\n');
    }

    let errors = findings.iter().filter(|f| f.severity == Severity::Error).count();
    let warnings = findings.iter().filter(|f| f.severity == Severity::Warning).count();
    out.push_str(&format!(
        "── Summary {}\n  {} error(s), {} warning(s)\n",
        "─".repeat(40),
        errors, warnings
    ));

    out
}

/// Render contract findings as JSON.
pub fn render_json(findings: &[Finding], consumer_name: &str, provider_name: &str) -> String {
    let items: Vec<String> = findings
        .iter()
        .map(|f| {
            format!(
                concat!(
                    "    {{\n",
                    "      \"code\": \"{}\",\n",
                    "      \"severity\": \"{}\",\n",
                    "      \"declaration\": \"{}\",\n",
                    "      \"message\": \"{}\"\n",
                    "    }}"
                ),
                f.code,
                f.severity,
                f.declaration,
                f.message.replace('"', "\\\"")
            )
        })
        .collect();

    format!(
        concat!(
            "{{\n",
            "  \"consumer\": \"{}\",\n",
            "  \"provider\": \"{}\",\n",
            "  \"findings\": [\n",
            "{}\n",
            "  ]\n",
            "}}\n"
        ),
        consumer_name,
        provider_name,
        items.join(",\n")
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use plat_manifest::*;

    fn make_manifest(name: &str, declarations: Vec<Declaration>) -> Manifest {
        Manifest {
            schema_version: "0.6".to_string(),
            name: name.to_string(),
            layers: vec![],
            type_aliases: vec![],
            custom_types: vec![],
            declarations,
            bindings: vec![],
            constraints: vec![],
            relations: vec![],
            meta: Default::default(),
        }
    }

    fn boundary(name: &str, ops: Vec<Op>) -> Declaration {
        Declaration {
            name: name.to_string(),
            kind: DeclKind::Boundary,
            ops,
            ..Declaration::default()
        }
    }

    fn operation(name: &str, needs: Vec<&str>) -> Declaration {
        Declaration {
            name: name.to_string(),
            kind: DeclKind::Operation,
            needs: needs.into_iter().map(|s| s.to_string()).collect(),
            ..Declaration::default()
        }
    }

    fn op(name: &str, inputs: usize) -> Op {
        Op {
            name: name.to_string(),
            inputs: (0..inputs)
                .map(|i| Field {
                    name: format!("p{i}"),
                    typ: "String".to_string(),
                })
                .collect(),
            outputs: vec![],
        }
    }

    #[test]
    fn ct001_missing_boundary() {
        let consumer = make_manifest(
            "order-service",
            vec![operation("PlaceOrder", vec!["PaymentGateway"])],
        );
        let provider = make_manifest("payment-service", vec![]);

        let findings = check(&consumer, &provider);
        assert_eq!(findings.len(), 1);
        assert_eq!(findings[0].code, "CT001");
    }

    #[test]
    fn ct001_local_boundary_ok() {
        let consumer = make_manifest(
            "order-service",
            vec![
                boundary("OrderRepo", vec![]),
                operation("PlaceOrder", vec!["OrderRepo"]),
            ],
        );
        let provider = make_manifest("payment-service", vec![]);

        let findings = check(&consumer, &provider);
        assert!(findings.is_empty());
    }

    #[test]
    fn ct002_missing_op() {
        let consumer = make_manifest(
            "order-service",
            vec![boundary("PaymentGateway", vec![op("charge", 2), op("refund", 1)])],
        );
        let provider = make_manifest(
            "payment-service",
            vec![boundary("PaymentGateway", vec![op("charge", 2)])],
        );

        let findings = check(&consumer, &provider);
        let ct002: Vec<_> = findings.iter().filter(|f| f.code == "CT002").collect();
        assert_eq!(ct002.len(), 1);
        assert!(ct002[0].message.contains("refund"));
    }

    #[test]
    fn ct003_param_mismatch() {
        let consumer = make_manifest(
            "order-service",
            vec![boundary("PaymentGateway", vec![op("charge", 2)])],
        );
        let provider = make_manifest(
            "payment-service",
            vec![boundary("PaymentGateway", vec![op("charge", 3)])],
        );

        let findings = check(&consumer, &provider);
        let ct003: Vec<_> = findings.iter().filter(|f| f.code == "CT003").collect();
        assert_eq!(ct003.len(), 1);
    }

    #[test]
    fn compatible_contracts() {
        let consumer = make_manifest(
            "order-service",
            vec![boundary("PaymentGateway", vec![op("charge", 2)])],
        );
        let provider = make_manifest(
            "payment-service",
            vec![boundary("PaymentGateway", vec![op("charge", 2), op("refund", 1)])],
        );

        let findings = check(&consumer, &provider);
        assert!(findings.is_empty());
    }
}

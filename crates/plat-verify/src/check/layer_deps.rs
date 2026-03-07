use std::collections::{HashMap, HashSet};

use crate::check::Finding;
use crate::config::Severity;
use plat_manifest::Manifest;
use plat_manifest::typemap;

/// L001: Check that declarations only reference types in allowed layers.
pub fn check(manifest: &Manifest) -> Vec<Finding> {
    let mut findings = Vec::new();

    // Build type -> layer map
    let type_to_layer: HashMap<&str, &str> = manifest
        .declarations
        .iter()
        .filter_map(|d| d.layer.as_deref().map(|l| (d.name.as_str(), l)))
        .collect();

    // Build allowed dependencies: layer -> set of allowed layers (includes self)
    let allowed_deps: HashMap<&str, HashSet<&str>> = manifest
        .layers
        .iter()
        .map(|l| {
            let mut deps: HashSet<&str> = l.depends.iter().map(|d| d.as_str()).collect();
            deps.insert(l.name.as_str());
            (l.name.as_str(), deps)
        })
        .collect();

    for decl in &manifest.declarations {
        let Some(ref decl_layer) = decl.layer else {
            continue;
        };
        let Some(allowed) = allowed_deps.get(decl_layer.as_str()) else {
            continue;
        };

        // Collect all type references from this declaration
        let mut type_refs: Vec<&str> = Vec::new();

        // From fields
        for field in &decl.fields {
            type_refs.extend(typemap::extract_type_refs(&field.typ));
        }

        // From ops (inputs and outputs)
        for op in &decl.ops {
            for param in &op.inputs {
                type_refs.extend(typemap::extract_type_refs(&param.typ));
            }
            for param in &op.outputs {
                type_refs.extend(typemap::extract_type_refs(&param.typ));
            }
        }

        // From needs
        for need in &decl.needs {
            type_refs.push(need.as_str());
        }

        // From implements
        if let Some(ref imp) = decl.implements {
            type_refs.push(imp.as_str());
        }

        // From injects
        for inject in &decl.injects {
            type_refs.extend(typemap::extract_type_refs(&inject.typ));
        }

        // Check each reference
        for type_ref in type_refs {
            let Some(ref_layer) = type_to_layer.get(type_ref) else {
                continue; // Unknown type (external or primitive), skip
            };
            if !allowed.contains(ref_layer) {
                findings.push(Finding {
                    code: "L001".to_string(),
                    severity: Severity::Error,
                    declaration: decl.name.clone(),
                    message: format!(
                        "layer \"{}\" cannot depend on layer \"{}\", but references \"{}\"",
                        decl_layer, ref_layer, type_ref
                    ),
                    expected: Some(format!(
                        "allowed layers: {}",
                        allowed.iter().copied().collect::<Vec<_>>().join(", ")
                    )),
                    source_file: None,
                    source_line: None,
                });
            }
        }
    }

    findings
}

#[cfg(test)]
mod tests {
    use super::*;
    use plat_manifest::*;

    fn make_manifest(declarations: Vec<Declaration>, bindings: Vec<Binding>) -> Manifest {
        Manifest {
            schema_version: "0.6".to_string(),
            name: "test".to_string(),
            custom_types: vec![],
            layers: vec![
                Layer {
                    name: "domain".to_string(),
                    depends: vec![],
                },
                Layer {
                    name: "port".to_string(),
                    depends: vec!["domain".to_string()],
                },
                Layer {
                    name: "app".to_string(),
                    depends: vec!["domain".to_string(), "port".to_string()],
                },
                Layer {
                    name: "infra".to_string(),
                    depends: vec![
                        "domain".to_string(),
                        "port".to_string(),
                        "app".to_string(),
                    ],
                },
            ],
            type_aliases: vec![],
            declarations,
            bindings,
            constraints: vec![],
            relations: vec![],
            meta: Default::default(),
        }
    }

    fn model(name: &str, layer: &str, fields: Vec<(&str, &str)>) -> Declaration {
        Declaration {
            name: name.to_string(),
            kind: DeclKind::Model,
            layer: Some(layer.to_string()),
            paths: vec![],
            fields: fields
                .into_iter()
                .map(|(n, t)| Field {
                    name: n.to_string(),
                    typ: t.to_string(),
                })
                .collect(),
            ops: vec![],
            inputs: vec![],
            outputs: vec![],
            needs: vec![],
            implements: None,
            injects: vec![],
            entries: vec![],
            service: None,
            meta: Default::default(),
        }
    }

    fn boundary(name: &str, layer: &str, ops: Vec<Op>) -> Declaration {
        Declaration {
            name: name.to_string(),
            kind: DeclKind::Boundary,
            layer: Some(layer.to_string()),
            paths: vec![],
            fields: vec![],
            ops,
            inputs: vec![],
            outputs: vec![],
            needs: vec![],
            implements: None,
            injects: vec![],
            entries: vec![],
            service: None,
            meta: Default::default(),
        }
    }

    fn operation(name: &str, layer: &str, needs: Vec<&str>) -> Declaration {
        Declaration {
            name: name.to_string(),
            kind: DeclKind::Operation,
            layer: Some(layer.to_string()),
            paths: vec![],
            fields: vec![],
            ops: vec![],
            inputs: vec![],
            outputs: vec![],
            needs: needs.into_iter().map(|s| s.to_string()).collect(),
            implements: None,
            injects: vec![],
            entries: vec![],
            service: None,
            meta: Default::default(),
        }
    }

    fn op(name: &str, inputs: Vec<(&str, &str)>, outputs: Vec<(&str, &str)>) -> Op {
        Op {
            name: name.to_string(),
            inputs: inputs
                .into_iter()
                .map(|(n, t)| Field {
                    name: n.to_string(),
                    typ: t.to_string(),
                })
                .collect(),
            outputs: outputs
                .into_iter()
                .map(|(n, t)| Field {
                    name: n.to_string(),
                    typ: t.to_string(),
                })
                .collect(),
        }
    }

    #[test]
    fn no_violation() {
        let m = make_manifest(
            vec![
                model("Order", "domain", vec![("id", "String")]),
                boundary(
                    "OrderRepo",
                    "port",
                    vec![op("Save", vec![("order", "Order")], vec![("err", "Error")])],
                ),
                operation("PlaceOrder", "app", vec!["OrderRepo"]),
            ],
            vec![],
        );
        let findings = check(&m);
        assert!(findings.is_empty(), "expected no violations: {:?}", findings);
    }

    #[test]
    fn field_type_violation() {
        // domain model references an infra type
        let mut m = make_manifest(
            vec![
                model("Order", "domain", vec![("repo", "PgPool")]),
                model("PgPool", "infra", vec![]),
            ],
            vec![],
        );
        m.declarations[0].fields = vec![Field {
            name: "repo".to_string(),
            typ: "PgPool".to_string(),
        }];
        let findings = check(&m);
        assert_eq!(findings.len(), 1);
        assert_eq!(findings[0].code, "L001");
        assert!(findings[0].message.contains("domain"));
        assert!(findings[0].message.contains("infra"));
        assert!(findings[0].message.contains("PgPool"));
    }

    #[test]
    fn op_param_violation() {
        // port boundary references an infra type in op params
        let m = make_manifest(
            vec![
                model("PgPool", "infra", vec![]),
                boundary(
                    "OrderRepo",
                    "port",
                    vec![op("Init", vec![("pool", "PgPool")], vec![])],
                ),
            ],
            vec![],
        );
        let findings = check(&m);
        assert_eq!(findings.len(), 1);
        assert_eq!(findings[0].code, "L001");
        assert!(findings[0].message.contains("PgPool"));
    }

    #[test]
    fn needs_violation() {
        // domain operation needs an infra type
        let m = make_manifest(
            vec![
                model("PgAdapter", "infra", vec![]),
                operation("PlaceOrder", "domain", vec!["PgAdapter"]),
            ],
            vec![],
        );
        let findings = check(&m);
        assert_eq!(findings.len(), 1);
        assert_eq!(findings[0].code, "L001");
    }

    #[test]
    fn same_layer_ok() {
        let m = make_manifest(
            vec![
                model("Order", "domain", vec![("status", "OrderStatus")]),
                model("OrderStatus", "domain", vec![]),
            ],
            vec![],
        );
        let findings = check(&m);
        assert!(findings.is_empty());
    }

    #[test]
    fn unknown_type_skipped() {
        // References to types not in the manifest are silently skipped
        let m = make_manifest(
            vec![model(
                "Order",
                "domain",
                vec![("id", "UUID"), ("status", "OrderStatus")],
            )],
            vec![],
        );
        let findings = check(&m);
        assert!(findings.is_empty());
    }

    #[test]
    fn nullable_and_generic_parse() {
        // "Order?" should resolve to Order, "List<Money>" should resolve to Money
        let m = make_manifest(
            vec![
                model("Money", "infra", vec![]),
                model(
                    "Cart",
                    "domain",
                    vec![("total", "Money?"), ("items", "List<Money>")],
                ),
            ],
            vec![],
        );
        let findings = check(&m);
        // Both Money? and List<Money> reference Money in infra from domain
        assert_eq!(findings.len(), 2, "expected 2 violations: {:?}", findings);
        assert!(findings.iter().all(|f| f.code == "L001"));
    }
}

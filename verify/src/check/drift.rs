use std::collections::HashSet;

use crate::check::Finding;
use crate::config::{Config, Severity};
use crate::extract::{FileFacts, TypeDefKind};
use crate::manifest::{DeclKind, Manifest};
use crate::naming;

/// T0xx: Detect drift — source artifacts not described in the manifest.
pub fn check(manifest: &Manifest, facts: &[FileFacts], config: &Config) -> Vec<Finding> {
    let mut findings = Vec::new();

    // Build set of expected type names (converted to source naming)
    let manifest_types: HashSet<String> = manifest
        .declarations
        .iter()
        .filter(|d| d.kind != DeclKind::Compose)
        .map(|d| naming::convert(&d.name, config.type_case()))
        .collect();

    // T001: source types not in manifest
    for file in facts {
        for td in &file.types {
            if !manifest_types.contains(&td.name) {
                findings.push(Finding {
                    code: "T001".to_string(),
                    severity: Severity::Info,
                    declaration: td.name.clone(),
                    message: format!(
                        "source type \"{}\" has no corresponding manifest declaration",
                        td.name
                    ),
                    expected: None,
                    source_file: Some(td.file.display().to_string()),
                    source_line: None,
                });
            }
        }
    }

    // T002: extra fields in source structs (compared to manifest models)
    for decl in &manifest.declarations {
        if decl.kind != DeclKind::Model {
            continue;
        }
        let type_name = naming::convert(&decl.name, config.type_case());
        let td = facts
            .iter()
            .flat_map(|f| &f.types)
            .find(|t| t.name == type_name && t.kind == TypeDefKind::Struct);

        let Some(td) = td else { continue };

        let manifest_fields: HashSet<String> = decl
            .fields
            .iter()
            .map(|f| naming::convert(&f.name, config.field_case()))
            .collect();

        for (src_field, _) in &td.fields {
            if !manifest_fields.contains(src_field) {
                findings.push(Finding {
                    code: "T002".to_string(),
                    severity: Severity::Info,
                    declaration: decl.name.clone(),
                    message: format!(
                        "source struct has field \"{}\" not declared in manifest",
                        src_field
                    ),
                    expected: None,
                    source_file: Some(td.file.display().to_string()),
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
    use crate::config::*;
    use crate::extract::TypeDef;
    use crate::manifest::*;
    use std::collections::HashMap;
    use std::path::PathBuf;

    fn test_config() -> Config {
        Config {
            source: SourceConfig {
                language: Language::Go,
                root: PathBuf::from("./src"),
                layer_dirs: HashMap::new(),
                layer_match: Default::default(),
            },
            types: HashMap::new(),
            naming: NamingConfig::default(),
            checks: ChecksConfig::default(),
        }
    }

    fn make_type(name: &str, kind: TypeDefKind, fields: Vec<(&str, &str)>) -> TypeDef {
        TypeDef {
            name: name.to_string(),
            kind,
            file: PathBuf::from("test.go"),
            fields: fields
                .into_iter()
                .map(|(n, t)| (n.to_string(), t.to_string()))
                .collect(),
            methods: vec![],
            implements: vec![],
        }
    }

    fn make_manifest(declarations: Vec<Declaration>) -> Manifest {
        Manifest {
            name: "test".to_string(),
            layers: vec![],
            declarations,
            bindings: vec![],
        }
    }

    #[test]
    fn t001_undeclared_source_type() {
        let manifest = make_manifest(vec![Declaration {
            name: "Order".to_string(),
            kind: DeclKind::Model,
            layer: None,
            fields: vec![],
            ops: vec![],
            needs: vec![],
            implements: None,
            injects: vec![],
            entries: vec![],
        }]);
        let facts = vec![FileFacts {
            path: PathBuf::from("test.go"),
            layer: None,
            types: vec![
                make_type("Order", TypeDefKind::Struct, vec![]),
                make_type("AuditLog", TypeDefKind::Struct, vec![]),
            ],
        }];
        let config = test_config();
        let findings = check(&manifest, &facts, &config);

        let t001: Vec<_> = findings.iter().filter(|f| f.code == "T001").collect();
        assert_eq!(t001.len(), 1);
        assert_eq!(t001[0].declaration, "AuditLog");
    }

    #[test]
    fn t001_all_types_declared() {
        let manifest = make_manifest(vec![
            Declaration {
                name: "Order".to_string(),
                kind: DeclKind::Model,
                layer: None,
                fields: vec![],
                ops: vec![],
                needs: vec![],
                implements: None,
                injects: vec![],
                entries: vec![],
            },
            Declaration {
                name: "OrderRepo".to_string(),
                kind: DeclKind::Boundary,
                layer: None,
                fields: vec![],
                ops: vec![],
                needs: vec![],
                implements: None,
                injects: vec![],
                entries: vec![],
            },
        ]);
        let facts = vec![FileFacts {
            path: PathBuf::from("test.go"),
            layer: None,
            types: vec![
                make_type("Order", TypeDefKind::Struct, vec![]),
                make_type("OrderRepo", TypeDefKind::Interface, vec![]),
            ],
        }];
        let config = test_config();
        let findings = check(&manifest, &facts, &config);
        assert!(findings.is_empty());
    }

    #[test]
    fn t002_extra_field() {
        let manifest = make_manifest(vec![Declaration {
            name: "Order".to_string(),
            kind: DeclKind::Model,
            layer: None,
            fields: vec![
                Field {
                    name: "Id".to_string(),
                    typ: "String".to_string(),
                },
                Field {
                    name: "Total".to_string(),
                    typ: "Float".to_string(),
                },
            ],
            ops: vec![],
            needs: vec![],
            implements: None,
            injects: vec![],
            entries: vec![],
        }]);
        let facts = vec![FileFacts {
            path: PathBuf::from("test.go"),
            layer: None,
            types: vec![make_type(
                "Order",
                TypeDefKind::Struct,
                vec![("Id", "string"), ("Total", "float64"), ("CreatedAt", "time.Time")],
            )],
        }];
        let config = test_config();
        let findings = check(&manifest, &facts, &config);

        let t002: Vec<_> = findings.iter().filter(|f| f.code == "T002").collect();
        assert_eq!(t002.len(), 1);
        assert!(t002[0].message.contains("CreatedAt"));
    }

    #[test]
    fn t002_no_extra_fields() {
        let manifest = make_manifest(vec![Declaration {
            name: "Order".to_string(),
            kind: DeclKind::Model,
            layer: None,
            fields: vec![
                Field {
                    name: "Id".to_string(),
                    typ: "String".to_string(),
                },
            ],
            ops: vec![],
            needs: vec![],
            implements: None,
            injects: vec![],
            entries: vec![],
        }]);
        let facts = vec![FileFacts {
            path: PathBuf::from("test.go"),
            layer: None,
            types: vec![make_type("Order", TypeDefKind::Struct, vec![("Id", "string")])],
        }];
        let config = test_config();
        let findings = check(&manifest, &facts, &config);
        assert!(findings.is_empty());
    }
}

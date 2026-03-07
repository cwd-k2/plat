use std::collections::HashSet;

use crate::check::Finding;
use crate::config::{Config, Severity};
use crate::extract::{FileFacts, TypeDefKind};
use plat_manifest::{DeclKind, Manifest};
use plat_manifest::naming;

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

    // T003: extra methods in source types (not declared as ops in manifest)
    for decl in &manifest.declarations {
        if decl.kind != DeclKind::Boundary {
            continue;
        }
        let type_name = naming::convert(&decl.name, config.type_case());
        let td = facts
            .iter()
            .flat_map(|f| &f.types)
            .find(|t| t.name == type_name && (t.kind == TypeDefKind::Interface || t.kind == TypeDefKind::Trait));

        let Some(td) = td else { continue };

        let manifest_ops: HashSet<String> = decl
            .ops
            .iter()
            .map(|o| naming::convert(&o.name, config.method_case()))
            .collect();

        for method in &td.methods {
            if !manifest_ops.contains(&method.name) {
                findings.push(Finding {
                    code: "T003".to_string(),
                    severity: Severity::Info,
                    declaration: decl.name.clone(),
                    message: format!(
                        "source type has method \"{}\" not declared as an op in manifest",
                        method.name
                    ),
                    expected: None,
                    source_file: Some(td.file.display().to_string()),
                    source_line: None,
                });
            }
        }
    }

    // T004: source type implements something not declared in manifest
    for decl in &manifest.declarations {
        if decl.kind != DeclKind::Adapter {
            continue;
        }
        let type_name = naming::convert(&decl.name, config.type_case());
        let td = facts
            .iter()
            .flat_map(|f| &f.types)
            .find(|t| t.name == type_name);

        let Some(td) = td else { continue };

        let manifest_impl = decl.implements.as_deref().map(|i| naming::convert(i, config.type_case()));

        for impl_name in &td.implements {
            let matches = manifest_impl.as_deref() == Some(impl_name.as_str());
            if !matches {
                findings.push(Finding {
                    code: "T004".to_string(),
                    severity: Severity::Info,
                    declaration: decl.name.clone(),
                    message: format!(
                        "source type implements \"{}\" which is not declared in manifest",
                        impl_name
                    ),
                    expected: manifest_impl.clone(),
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
    use plat_manifest::*;
    use std::collections::HashMap;
    use std::path::PathBuf;

    fn test_config() -> Config {
        Config {
            source: SourceConfig {
                language: Language::Go,
                root: PathBuf::from("./src"),
                layer_dirs: HashMap::new(),
                layer_match: Default::default(),
                exclude: Default::default(),
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
            schema_version: "0.6".to_string(),
            name: "test".to_string(),
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

    fn test_decl(name: &str, kind: DeclKind, fields: Vec<Field>) -> Declaration {
        Declaration {
            name: name.to_string(),
            kind,
            layer: None,
            paths: vec![],
            fields,
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

    #[test]
    fn t001_undeclared_source_type() {
        let manifest = make_manifest(vec![test_decl("Order", DeclKind::Model, vec![])]);
        let facts = vec![FileFacts {
            path: PathBuf::from("test.go"),
            layer: None,
            imports: vec![],
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
            test_decl("Order", DeclKind::Model, vec![]),
            test_decl("OrderRepo", DeclKind::Boundary, vec![]),
        ]);
        let facts = vec![FileFacts {
            path: PathBuf::from("test.go"),
            layer: None,
            imports: vec![],
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
        let manifest = make_manifest(vec![test_decl(
            "Order",
            DeclKind::Model,
            vec![
                Field { name: "Id".to_string(), typ: "String".to_string() },
                Field { name: "Total".to_string(), typ: "Float".to_string() },
            ],
        )]);
        let facts = vec![FileFacts {
            path: PathBuf::from("test.go"),
            layer: None,
            imports: vec![],
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

    fn make_method(name: &str) -> crate::extract::MethodDef {
        crate::extract::MethodDef {
            name: name.to_string(),
            params: vec![],
            returns: vec![],
        }
    }

    #[test]
    fn t003_surplus_method() {
        let mut boundary = test_decl("OrderRepo", DeclKind::Boundary, vec![]);
        boundary.ops = vec![Op {
            name: "Save".to_string(),
            inputs: vec![],
            outputs: vec![],
        }];
        let manifest = make_manifest(vec![boundary]);

        let mut td = make_type("OrderRepo", TypeDefKind::Interface, vec![]);
        td.methods = vec![make_method("Save"), make_method("Delete")];

        let facts = vec![FileFacts {
            path: PathBuf::from("test.go"),
            layer: None,
            imports: vec![],
            types: vec![td],
        }];
        let config = test_config();
        let findings = check(&manifest, &facts, &config);

        let t003: Vec<_> = findings.iter().filter(|f| f.code == "T003").collect();
        assert_eq!(t003.len(), 1);
        assert!(t003[0].message.contains("Delete"));
    }

    #[test]
    fn t003_no_surplus() {
        let mut boundary = test_decl("OrderRepo", DeclKind::Boundary, vec![]);
        boundary.ops = vec![
            Op { name: "Save".to_string(), inputs: vec![], outputs: vec![] },
            Op { name: "FindById".to_string(), inputs: vec![], outputs: vec![] },
        ];
        let manifest = make_manifest(vec![boundary]);

        let mut td = make_type("OrderRepo", TypeDefKind::Interface, vec![]);
        td.methods = vec![make_method("Save"), make_method("FindById")];

        let facts = vec![FileFacts {
            path: PathBuf::from("test.go"),
            layer: None,
            imports: vec![],
            types: vec![td],
        }];
        let config = test_config();
        let findings = check(&manifest, &facts, &config);
        assert!(findings.is_empty());
    }

    #[test]
    fn t004_undeclared_implements() {
        let mut adapter = test_decl("PgOrderRepo", DeclKind::Adapter, vec![]);
        adapter.implements = Some("OrderRepo".to_string());
        let manifest = make_manifest(vec![adapter]);

        let mut td = make_type("PgOrderRepo", TypeDefKind::Struct, vec![]);
        td.implements = vec!["OrderRepo".to_string(), "AuditLogger".to_string()];

        let facts = vec![FileFacts {
            path: PathBuf::from("test.go"),
            layer: None,
            imports: vec![],
            types: vec![td],
        }];
        let config = test_config();
        let findings = check(&manifest, &facts, &config);

        let t004: Vec<_> = findings.iter().filter(|f| f.code == "T004").collect();
        assert_eq!(t004.len(), 1);
        assert!(t004[0].message.contains("AuditLogger"));
    }

    #[test]
    fn t004_no_undeclared() {
        let mut adapter = test_decl("PgOrderRepo", DeclKind::Adapter, vec![]);
        adapter.implements = Some("OrderRepo".to_string());
        let manifest = make_manifest(vec![adapter]);

        let mut td = make_type("PgOrderRepo", TypeDefKind::Struct, vec![]);
        td.implements = vec!["OrderRepo".to_string()];

        let facts = vec![FileFacts {
            path: PathBuf::from("test.go"),
            layer: None,
            imports: vec![],
            types: vec![td],
        }];
        let config = test_config();
        let findings = check(&manifest, &facts, &config);
        assert!(findings.is_empty());
    }

    #[test]
    fn t002_no_extra_fields() {
        let manifest = make_manifest(vec![test_decl(
            "Order",
            DeclKind::Model,
            vec![Field { name: "Id".to_string(), typ: "String".to_string() }],
        )]);
        let facts = vec![FileFacts {
            path: PathBuf::from("test.go"),
            layer: None,
            imports: vec![],
            types: vec![make_type("Order", TypeDefKind::Struct, vec![("Id", "string")])],
        }];
        let config = test_config();
        let findings = check(&manifest, &facts, &config);
        assert!(findings.is_empty());
    }
}

use crate::check::Finding;
use crate::config::{Config, Severity};
use crate::extract::FileFacts;

/// N0xx: Check that source type/field/method names conform to naming conventions.
///
/// Unlike structure checks (S0xx) which compare manifest vs source,
/// naming checks validate source names against the configured case convention
/// regardless of the manifest.
pub fn check(facts: &[FileFacts], config: &Config) -> Vec<Finding> {
    let mut findings = Vec::new();

    let type_case = config.type_case();
    let field_case = config.field_case();
    let method_case = config.method_case();

    for file in facts {
        for td in &file.types {
            // N001: type name case
            if !plat_manifest::naming::matches_case(&td.name, type_case) {
                let expected = plat_manifest::naming::convert(&td.name, type_case);
                findings.push(Finding {
                    code: "N001".to_string(),
                    severity: Severity::Warning,
                    declaration: td.name.clone(),
                    message: format!(
                        "type \"{}\" does not match {:?} convention (expected \"{}\")",
                        td.name, type_case, expected
                    ),
                    expected: Some(expected),
                    source_file: Some(file.path.to_string_lossy().to_string()),
                    source_line: None,
                });
            }

            // N002: field name case
            for (field_name, _) in &td.fields {
                if !plat_manifest::naming::matches_case(field_name, field_case) {
                    let expected = plat_manifest::naming::convert(field_name, field_case);
                    findings.push(Finding {
                        code: "N002".to_string(),
                        severity: Severity::Info,
                        declaration: td.name.clone(),
                        message: format!(
                            "field \"{}\" does not match {:?} convention (expected \"{}\")",
                            field_name, field_case, expected
                        ),
                        expected: Some(expected),
                        source_file: Some(file.path.to_string_lossy().to_string()),
                        source_line: None,
                    });
                }
            }

            // N003: method name case
            for method in &td.methods {
                if !plat_manifest::naming::matches_case(&method.name, method_case) {
                    let expected = plat_manifest::naming::convert(&method.name, method_case);
                    findings.push(Finding {
                        code: "N003".to_string(),
                        severity: Severity::Info,
                        declaration: td.name.clone(),
                        message: format!(
                            "method \"{}\" does not match {:?} convention (expected \"{}\")",
                            method.name, method_case, expected
                        ),
                        expected: Some(expected),
                        source_file: Some(file.path.to_string_lossy().to_string()),
                        source_line: None,
                    });
                }
            }
        }
    }

    findings
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::*;
    use crate::extract::*;
    use plat_manifest::Language;
    use std::path::PathBuf;

    fn test_config(lang: Language) -> Config {
        Config {
            source: SourceConfig {
                language: lang,
                root: PathBuf::from("./src"),
                layer_dirs: Default::default(),
                layer_match: LayerMatch::Prefix,
                exclude: Default::default(),
            },
            types: Default::default(),
            naming: Default::default(),
            checks: Default::default(),
        }
    }

    fn make_type(name: &str, fields: Vec<(&str, &str)>, methods: Vec<&str>) -> TypeDef {
        TypeDef {
            name: name.to_string(),
            kind: TypeDefKind::Struct,
            file: PathBuf::from("test.go"),
            fields: fields
                .into_iter()
                .map(|(n, t)| (n.to_string(), t.to_string()))
                .collect(),
            methods: methods
                .into_iter()
                .map(|n| MethodDef {
                    name: n.to_string(),
                    params: vec![],
                    returns: vec![],
                })
                .collect(),
            implements: vec![],
        }
    }

    fn make_facts(types: Vec<TypeDef>) -> Vec<FileFacts> {
        vec![FileFacts {
            path: PathBuf::from("test.go"),
            layer: None,
            types,
            imports: vec![],
        }]
    }

    #[test]
    fn n001_go_type_name() {
        let config = test_config(Language::Go);
        let facts = make_facts(vec![
            make_type("Order", vec![], vec![]),       // OK: PascalCase
            make_type("orderItem", vec![], vec![]),   // violation
        ]);
        let findings = check(&facts, &config);
        let n001: Vec<_> = findings.iter().filter(|f| f.code == "N001").collect();
        assert_eq!(n001.len(), 1);
        assert_eq!(n001[0].declaration, "orderItem");
    }

    #[test]
    fn n002_rust_field_name() {
        let config = test_config(Language::Rust);
        let facts = make_facts(vec![make_type(
            "Order",
            vec![("order_id", "String"), ("Total", "f64")], // Total violates snake_case
            vec![],
        )]);
        let findings = check(&facts, &config);
        let n002: Vec<_> = findings.iter().filter(|f| f.code == "N002").collect();
        assert_eq!(n002.len(), 1);
        assert!(n002[0].message.contains("Total"));
    }

    #[test]
    fn n003_ts_method_name() {
        let config = test_config(Language::TypeScript);
        let facts = make_facts(vec![make_type(
            "OrderService",
            vec![],
            vec!["placeOrder", "CancelOrder"], // CancelOrder violates camelCase
        )]);
        let findings = check(&facts, &config);
        let n003: Vec<_> = findings.iter().filter(|f| f.code == "N003").collect();
        assert_eq!(n003.len(), 1);
        assert!(n003[0].message.contains("CancelOrder"));
    }

    #[test]
    fn all_conventions_respected() {
        let config = test_config(Language::Go);
        let facts = make_facts(vec![make_type(
            "Order",
            vec![("ID", "string"), ("Total", "float64")],
            vec!["Save", "FindById"],
        )]);
        let findings = check(&facts, &config);
        assert!(findings.is_empty());
    }
}

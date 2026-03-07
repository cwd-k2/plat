use crate::check::Finding;
use crate::config::{Config, Severity};
use crate::extract::{FileFacts, TypeDefKind};
use crate::manifest::{DeclKind, Manifest};
use crate::naming;
use crate::typemap;

/// S0xx: Check structural conformance (fields, methods).
pub fn check(manifest: &Manifest, facts: &[FileFacts], config: &Config) -> Vec<Finding> {
    let mut findings = Vec::new();
    let lang = config.source.language;
    let default_map = typemap::defaults(lang);

    for decl in &manifest.declarations {
        let type_name = naming::convert(&decl.name, config.type_case());
        let found = find_type_anywhere(facts, &type_name);
        let Some(td) = found else { continue }; // existence check handles missing types

        // S001/S002: model field checks
        if decl.kind == DeclKind::Model && td.kind == TypeDefKind::Struct {
            for field in &decl.fields {
                let src_field_name = naming::convert(&field.name, config.field_case());
                let matched = td.fields.iter().find(|(n, _)| *n == src_field_name);
                match matched {
                    None => {
                        findings.push(Finding {
                            code: "S001".to_string(),
                            severity: Severity::Warning,
                            declaration: decl.name.clone(),
                            message: format!("missing field \"{}\"", field.name),
                            expected: Some(format!(
                                "{} ({})",
                                field.typ,
                                typemap::resolve(&field.typ, lang, &default_map, &config.types)
                            )),
                            source_file: Some(td.file.display().to_string()),
                            source_line: None,
                        });
                    }
                    Some((_, src_type)) => {
                        let expected = typemap::resolve(&field.typ, lang, &default_map, &config.types);
                        if !types_match(src_type, &expected) {
                            findings.push(Finding {
                                code: "S002".to_string(),
                                severity: Severity::Info,
                                declaration: decl.name.clone(),
                                message: format!(
                                    "field \"{}\" type mismatch: expected {}, found {}",
                                    field.name, expected, src_type
                                ),
                                expected: Some(expected),
                                source_file: Some(td.file.display().to_string()),
                                source_line: None,
                            });
                        }
                    }
                }
            }
        }

        // S003/S004: boundary op checks
        if decl.kind == DeclKind::Boundary
            && (td.kind == TypeDefKind::Interface || td.kind == TypeDefKind::Trait)
        {
            for op in &decl.ops {
                let method_name = naming::convert(&op.name, config.method_case());
                let matched = td.methods.iter().find(|m| m.name == method_name);
                match matched {
                    None => {
                        findings.push(Finding {
                            code: "S003".to_string(),
                            severity: Severity::Error,
                            declaration: decl.name.clone(),
                            message: format!("missing method \"{}\"", op.name),
                            expected: Some(format!("method {} on {}", method_name, type_name)),
                            source_file: Some(td.file.display().to_string()),
                            source_line: None,
                        });
                    }
                    Some(method) => {
                        // Count non-error params from manifest
                        let manifest_param_count = op
                            .inputs
                            .iter()
                            .filter(|p| !typemap::is_error_type(&p.typ))
                            .count();
                        let source_param_count = method.params.len();
                        if manifest_param_count != source_param_count {
                            findings.push(Finding {
                                code: "S004".to_string(),
                                severity: Severity::Warning,
                                declaration: decl.name.clone(),
                                message: format!(
                                    "method \"{}\" parameter count mismatch: expected {}, found {}",
                                    op.name, manifest_param_count, source_param_count
                                ),
                                expected: None,
                                source_file: Some(td.file.display().to_string()),
                                source_line: None,
                            });
                        }
                    }
                }
            }
        }

        // S005: adapter inject checks
        if decl.kind == DeclKind::Adapter && td.kind == TypeDefKind::Struct {
            for inject in &decl.injects {
                let field_name = naming::convert(&inject.name, config.field_case());
                let found = td.fields.iter().any(|(n, _)| *n == field_name);
                if !found {
                    findings.push(Finding {
                        code: "S005".to_string(),
                        severity: Severity::Warning,
                        declaration: decl.name.clone(),
                        message: format!("missing injected dependency \"{}\"", inject.name),
                        expected: Some(inject.typ.clone()),
                        source_file: Some(td.file.display().to_string()),
                        source_line: None,
                    });
                }
            }
        }

        // S006: operation needs field checks
        if decl.kind == DeclKind::Operation && td.kind == TypeDefKind::Struct {
            for need in &decl.needs {
                let field_name = naming::convert(need, config.field_case());
                let found = td.fields.iter().any(|(n, _)| *n == field_name);
                if !found {
                    findings.push(Finding {
                        code: "S006".to_string(),
                        severity: Severity::Info,
                        declaration: decl.name.clone(),
                        message: format!(
                            "needs \"{}\" but no matching field \"{}\"",
                            need, field_name
                        ),
                        expected: Some(field_name),
                        source_file: Some(td.file.display().to_string()),
                        source_line: None,
                    });
                }
            }
        }
    }

    findings
}

fn find_type_anywhere<'a>(facts: &'a [FileFacts], name: &str) -> Option<&'a crate::extract::TypeDef> {
    facts
        .iter()
        .flat_map(|f| &f.types)
        .find(|td| td.name == name)
}

/// Lenient type comparison: strips whitespace and common wrappers.
fn types_match(source: &str, expected: &str) -> bool {
    let s = source.trim();
    let e = expected.trim();
    s == e
}

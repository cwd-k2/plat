use crate::check::{find_type_by_name, Finding};
use crate::config::{Config, Severity};
use crate::extract::{FileFacts, TypeDefKind};
use plat_manifest::{DeclKind, Manifest};
use plat_manifest::typemap;

/// S0xx: Check structural conformance (fields, methods).
pub fn check(manifest: &Manifest, facts: &[FileFacts], config: &Config) -> Vec<Finding> {
    let mut findings = Vec::new();
    let lang = config.source.language;
    let default_map = typemap::defaults(lang);

    for decl in &manifest.declarations {
        let type_name = config.convert_type_name(&decl.name);
        let found = find_type_by_name(facts, &type_name, config);
        let Some(td) = found else { continue }; // existence check handles missing types

        // S001/S002: model field checks
        if decl.kind == DeclKind::Model && td.kind == TypeDefKind::Struct {
            for field in &decl.fields {
                let src_field_name = config.convert_field_name(&field.name);
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
                let method_name = config.convert_method_name(&op.name);
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
                let field_name = config.convert_field_name(&inject.name);
                // Try converted name, raw name, and camelCase (Go unexported fields)
                let camel = plat_manifest::naming::convert(&inject.name, plat_manifest::Case::Camel);
                let found = td.fields.iter().any(|(n, _)| {
                    *n == field_name || *n == inject.name || *n == camel
                });
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
                let field_name = config.convert_field_name(need);
                let camel = plat_manifest::naming::convert(need, plat_manifest::Case::Camel);
                // Check field name (converted, raw, camelCase) OR field type containing the declaration name
                let found = td.fields.iter().any(|(n, t)| {
                    *n == field_name || *n == *need || *n == camel || type_contains_name(t, need)
                });
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

/// Lenient type comparison: strips pointer prefix, package qualifier, and slice/array wrappers.
fn types_match(source: &str, expected: &str) -> bool {
    let s = normalize_type(source);
    let e = normalize_type(expected);
    s == e
}

/// Normalize a type string for comparison: strip pointer, package qualifier.
fn normalize_type(t: &str) -> String {
    let t = t.trim();
    // Strip pointer prefix
    let t = t.trim_start_matches('*');
    // Strip package qualifier (keep only the type name after last dot)
    // But preserve slice/map prefixes
    if let Some(pos) = t.rfind('.') {
        // Check if this is inside generics or a qualified name
        let before = &t[..pos];
        if !before.contains('[') && !before.contains('<') {
            return t[pos + 1..].to_string();
        }
    }
    t.to_string()
}

/// Check if a source type string contains a declaration name.
/// Handles package-qualified types like `port.OrderRepository`.
fn type_contains_name(source_type: &str, decl_name: &str) -> bool {
    // Exact suffix match after dot (package.Type) or exact match
    source_type == decl_name
        || source_type.ends_with(&format!(".{}", decl_name))
}

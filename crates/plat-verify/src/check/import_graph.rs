use std::collections::{HashMap, HashSet};

use crate::check::Finding;
use crate::config::{Config, LayerMatch, Severity};
use crate::extract::FileFacts;
use plat_manifest::Manifest;

/// I001: Check that source file imports respect layer dependency rules.
///
/// For each file whose layer is known, resolve the layer of each import
/// path using the same `layer_dirs` mapping. If the import targets a
/// layer that is not allowed by the manifest, report a violation.
pub fn check(manifest: &Manifest, facts: &[FileFacts], config: &Config) -> Vec<Finding> {
    let mut findings = Vec::new();

    let layer_dirs = &config.source.layer_dirs;
    if layer_dirs.is_empty() {
        return findings; // cannot resolve layers without mapping
    }

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

    for file in facts {
        let Some(ref src_layer) = file.layer else {
            continue;
        };
        let Some(allowed) = allowed_deps.get(src_layer.as_str()) else {
            continue;
        };

        for import_path in &file.imports {
            let target_layer = resolve_import_layer(
                import_path,
                layer_dirs,
                config.source.layer_match,
            );
            let Some(ref target_layer) = target_layer else {
                continue; // cannot determine layer — skip
            };
            if !allowed.contains(target_layer.as_str()) {
                findings.push(Finding {
                    code: "I001".to_string(),
                    severity: Severity::Error,
                    declaration: file
                        .path
                        .file_name()
                        .and_then(|n| n.to_str())
                        .unwrap_or("?")
                        .to_string(),
                    message: format!(
                        "file in layer \"{}\" imports \"{}\" from layer \"{}\"",
                        src_layer, import_path, target_layer
                    ),
                    expected: Some(format!(
                        "allowed layers: {}",
                        allowed.iter().copied().collect::<Vec<_>>().join(", ")
                    )),
                    source_file: Some(file.path.to_string_lossy().to_string()),
                    source_line: None,
                });
            }
        }
    }

    findings
}

/// Resolve the layer of an import path using the layer_dirs mapping.
///
/// Splits the import path into components (by `/`, `::`, or `\`) and checks
/// if any component matches a layer_dirs value.
fn resolve_import_layer(
    import_path: &str,
    layer_dirs: &HashMap<String, String>,
    layer_match: LayerMatch,
) -> Option<String> {
    match layer_match {
        LayerMatch::Prefix => {
            // Check if the import path starts with a layer directory
            layer_dirs
                .iter()
                .filter(|(_, dir)| import_path.starts_with(dir.as_str()))
                .max_by_key(|(_, dir)| dir.len())
                .map(|(layer, _)| layer.clone())
        }
        LayerMatch::Component => {
            // Split by common separators and match against layer_dirs values
            let components: Vec<&str> = import_path
                .split(|c: char| c == '/' || c == '\\' || c == ':')
                .filter(|s| !s.is_empty())
                .collect();
            layer_dirs
                .iter()
                .filter(|(_, dir)| components.contains(&dir.as_str()))
                .max_by_key(|(_, dir)| dir.len())
                .map(|(layer, _)| layer.clone())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::extract::{FileFacts, TypeDef, TypeDefKind};
    use plat_manifest::*;
    use std::path::PathBuf;

    fn test_config(layer_dirs: Vec<(&str, &str)>) -> Config {
        Config {
            source: crate::config::SourceConfig {
                language: Language::Go,
                root: PathBuf::from("./src"),
                layer_dirs: layer_dirs
                    .into_iter()
                    .map(|(k, v)| (k.to_string(), v.to_string()))
                    .collect(),
                layer_match: LayerMatch::Component,
            },
            types: Default::default(),
            naming: Default::default(),
            checks: Default::default(),
        }
    }

    fn test_manifest() -> Manifest {
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
                    name: "infra".to_string(),
                    depends: vec!["domain".to_string(), "port".to_string()],
                },
            ],
            type_aliases: vec![],
            declarations: vec![],
            bindings: vec![],
            constraints: vec![],
            relations: vec![],
            meta: Default::default(),
        }
    }

    fn make_facts(path: &str, layer: &str, imports: Vec<&str>) -> FileFacts {
        FileFacts {
            path: PathBuf::from(path),
            layer: Some(layer.to_string()),
            types: vec![TypeDef {
                name: "Dummy".to_string(),
                kind: TypeDefKind::Struct,
                file: PathBuf::from(path),
                fields: vec![],
                methods: vec![],
                implements: vec![],
            }],
            imports: imports.into_iter().map(|s| s.to_string()).collect(),
        }
    }

    #[test]
    fn i001_domain_imports_infra() {
        let manifest = test_manifest();
        let config = test_config(vec![
            ("domain", "domain"),
            ("port", "port"),
            ("infra", "infra"),
        ]);
        let facts = vec![make_facts(
            "src/domain/order.go",
            "domain",
            vec!["myapp/infra/postgres"],
        )];
        let findings = check(&manifest, &facts, &config);
        assert_eq!(findings.len(), 1);
        assert_eq!(findings[0].code, "I001");
        assert!(findings[0].message.contains("domain"));
        assert!(findings[0].message.contains("infra"));
    }

    #[test]
    fn allowed_import_no_violation() {
        let manifest = test_manifest();
        let config = test_config(vec![
            ("domain", "domain"),
            ("port", "port"),
            ("infra", "infra"),
        ]);
        let facts = vec![make_facts(
            "src/infra/repo.go",
            "infra",
            vec!["myapp/domain/order", "myapp/port/repository"],
        )];
        let findings = check(&manifest, &facts, &config);
        assert!(findings.is_empty());
    }

    #[test]
    fn same_layer_import_ok() {
        let manifest = test_manifest();
        let config = test_config(vec![("domain", "domain")]);
        let facts = vec![make_facts(
            "src/domain/order.go",
            "domain",
            vec!["myapp/domain/money"],
        )];
        let findings = check(&manifest, &facts, &config);
        assert!(findings.is_empty());
    }

    #[test]
    fn unknown_layer_import_skipped() {
        let manifest = test_manifest();
        let config = test_config(vec![("domain", "domain")]);
        let facts = vec![make_facts(
            "src/domain/order.go",
            "domain",
            vec!["fmt", "encoding/json"],
        )];
        let findings = check(&manifest, &facts, &config);
        assert!(findings.is_empty());
    }

    #[test]
    fn prefix_mode() {
        let manifest = test_manifest();
        let mut config = test_config(vec![
            ("domain", "domain/"),
            ("infra", "infra/"),
        ]);
        config.source.layer_match = LayerMatch::Prefix;
        let facts = vec![make_facts(
            "src/domain/order.go",
            "domain",
            vec!["infra/postgres"],
        )];
        let findings = check(&manifest, &facts, &config);
        assert_eq!(findings.len(), 1);
        assert_eq!(findings[0].code, "I001");
    }

    #[test]
    fn rust_crate_path() {
        let manifest = test_manifest();
        let config = test_config(vec![
            ("domain", "domain"),
            ("infra", "infra"),
        ]);
        let facts = vec![make_facts(
            "src/domain/order.rs",
            "domain",
            vec!["crate::infra::postgres::PgPool"],
        )];
        let findings = check(&manifest, &facts, &config);
        assert_eq!(findings.len(), 1);
        assert_eq!(findings[0].code, "I001");
    }
}

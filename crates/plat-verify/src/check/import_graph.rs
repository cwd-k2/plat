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

    // I002: import cycle detection
    findings.extend(check_cycles(facts, config));

    findings
}

/// I002: Detect import cycles among source files.
///
/// Builds a directed graph from file → imported files and reports any cycles.
/// Import paths are resolved to known files using layer_dirs and path heuristics.
fn check_cycles(facts: &[FileFacts], config: &Config) -> Vec<Finding> {
    let layer_dirs = &config.source.layer_dirs;

    // Build file index: layer component → list of file indices
    let mut layer_files: HashMap<String, Vec<usize>> = HashMap::new();
    for (i, f) in facts.iter().enumerate() {
        if let Some(ref layer) = f.layer {
            layer_files.entry(layer.clone()).or_default().push(i);
        }
    }

    // Build adjacency: file index → set of file indices it imports
    let mut adj: HashMap<usize, HashSet<usize>> = HashMap::new();
    for (i, f) in facts.iter().enumerate() {
        for import_path in &f.imports {
            // Try to resolve import to a known file
            let target_layer = resolve_import_layer(
                import_path,
                layer_dirs,
                config.source.layer_match,
            );
            if let Some(ref layer) = target_layer {
                if let Some(targets) = layer_files.get(layer) {
                    for &t in targets {
                        if t != i {
                            adj.entry(i).or_default().insert(t);
                        }
                    }
                }
            }
        }
    }

    // DFS cycle detection
    let n = facts.len();
    let mut color = vec![0u8; n]; // 0=white, 1=grey, 2=black
    let mut findings = Vec::new();
    let mut reported_cycles: HashSet<Vec<usize>> = HashSet::new();

    for start in 0..n {
        if color[start] == 0 {
            let mut path = Vec::new();
            dfs_cycle(
                start,
                &adj,
                &mut color,
                &mut path,
                facts,
                &mut findings,
                &mut reported_cycles,
            );
        }
    }

    findings
}

fn dfs_cycle(
    node: usize,
    adj: &HashMap<usize, HashSet<usize>>,
    color: &mut [u8],
    path: &mut Vec<usize>,
    facts: &[FileFacts],
    findings: &mut Vec<Finding>,
    reported: &mut HashSet<Vec<usize>>,
) {
    color[node] = 1; // grey
    path.push(node);

    if let Some(neighbors) = adj.get(&node) {
        for &next in neighbors {
            if color[next] == 1 {
                // Found a cycle — extract the cycle from path
                if let Some(pos) = path.iter().position(|&n| n == next) {
                    let mut cycle: Vec<usize> = path[pos..].to_vec();
                    // Normalize: rotate so smallest index is first
                    if let Some(min_pos) = cycle.iter().enumerate().min_by_key(|(_, &v)| v).map(|(i, _)| i) {
                        cycle.rotate_left(min_pos);
                    }
                    if reported.insert(cycle.clone()) {
                        let names: Vec<String> = cycle
                            .iter()
                            .map(|&i| {
                                facts[i]
                                    .path
                                    .file_name()
                                    .and_then(|n| n.to_str())
                                    .unwrap_or("?")
                                    .to_string()
                            })
                            .collect();
                        let layers: Vec<String> = cycle
                            .iter()
                            .filter_map(|&i| facts[i].layer.clone())
                            .collect();
                        let layer_info = if !layers.is_empty() {
                            format!(" (layers: {})", layers.join(" → "))
                        } else {
                            String::new()
                        };
                        findings.push(Finding {
                            code: "I002".to_string(),
                            severity: Severity::Warning,
                            declaration: names[0].clone(),
                            message: format!(
                                "import cycle: {}{}",
                                names.join(" → "),
                                layer_info
                            ),
                            expected: None,
                            source_file: Some(facts[cycle[0]].path.to_string_lossy().to_string()),
                            source_line: None,
                        });
                    }
                }
            } else if color[next] == 0 {
                dfs_cycle(next, adj, color, path, facts, findings, reported);
            }
        }
    }

    path.pop();
    color[node] = 2; // black
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

    #[test]
    fn i002_import_cycle() {
        let manifest = test_manifest();
        let config = test_config(vec![
            ("domain", "domain"),
            ("port", "port"),
        ]);
        // domain/a.go imports port/b, port/b.go imports domain/a → cycle
        let facts = vec![
            make_facts("src/domain/a.go", "domain", vec!["myapp/port/b"]),
            make_facts("src/port/b.go", "port", vec!["myapp/domain/a"]),
        ];
        let findings = check(&manifest, &facts, &config);
        let i002: Vec<_> = findings.iter().filter(|f| f.code == "I002").collect();
        assert_eq!(i002.len(), 1, "expected 1 cycle: {:?}", i002);
        assert!(i002[0].message.contains("import cycle"));
    }

    #[test]
    fn i002_no_cycle() {
        let manifest = test_manifest();
        let config = test_config(vec![
            ("domain", "domain"),
            ("port", "port"),
            ("infra", "infra"),
        ]);
        // Linear: infra → port → domain (no cycle)
        let facts = vec![
            make_facts("src/domain/order.go", "domain", vec![]),
            make_facts("src/port/repo.go", "port", vec!["myapp/domain/order"]),
            make_facts("src/infra/pg.go", "infra", vec!["myapp/port/repo"]),
        ];
        let findings = check(&manifest, &facts, &config);
        let i002: Vec<_> = findings.iter().filter(|f| f.code == "I002").collect();
        assert!(i002.is_empty());
    }
}

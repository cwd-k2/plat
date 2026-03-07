//! P1: Reverse-engineer an initial manifest from source code.
//!
//! Extracts types from source using tree-sitter and generates a manifest
//! that reflects the current codebase structure. The output serves as a
//! starting point for iterative refinement (Reflexion Model bootstrapping).

use crate::config::Config;
use crate::extract::{self, FileFacts, TypeDefKind};
use plat_manifest::{
    Declaration, DeclKind, Field, Layer, Manifest, Op,
};

use std::collections::BTreeSet;

/// Generate an initial manifest from extracted source facts.
pub fn generate(
    name: &str,
    facts: &[FileFacts],
    config: &Config,
) -> Manifest {
    let mut declarations = Vec::new();
    let mut layers_seen = BTreeSet::new();

    for file in facts {
        if let Some(ref layer) = file.layer {
            layers_seen.insert(layer.clone());
        }

        for td in &file.types {
            let (kind, fields, ops) = match td.kind {
                TypeDefKind::Struct | TypeDefKind::Class | TypeDefKind::Enum => {
                    let fields: Vec<Field> = td
                        .fields
                        .iter()
                        .map(|(n, t)| Field {
                            name: n.clone(),
                            typ: t.clone(),
                        })
                        .collect();
                    (DeclKind::Model, fields, vec![])
                }
                TypeDefKind::Interface | TypeDefKind::Trait => {
                    let ops: Vec<Op> = td
                        .methods
                        .iter()
                        .map(|m| Op {
                            name: m.name.clone(),
                            inputs: m
                                .params
                                .iter()
                                .map(|(n, t)| Field {
                                    name: n.clone(),
                                    typ: t.clone(),
                                })
                                .collect(),
                            outputs: m
                                .returns
                                .iter()
                                .map(|t| Field {
                                    name: String::new(),
                                    typ: t.clone(),
                                })
                                .collect(),
                        })
                        .collect();
                    (DeclKind::Boundary, vec![], ops)
                }
            };

            // Check if this struct implements an interface → Adapter
            let (final_kind, implements) = if kind == DeclKind::Model
                && !td.implements.is_empty()
                && td.methods.iter().any(|_| true)
            {
                (DeclKind::Adapter, td.implements.first().cloned())
            } else {
                (kind, None)
            };

            let path = file
                .path
                .strip_prefix(&config.source.root)
                .map(|p| p.display().to_string())
                .unwrap_or_else(|_| file.path.display().to_string());

            declarations.push(Declaration {
                name: td.name.clone(),
                kind: final_kind,
                layer: file.layer.clone(),
                paths: vec![path],
                fields,
                ops,
                inputs: vec![],
                outputs: vec![],
                needs: vec![],
                implements,
                injects: vec![],
                entries: vec![],
                service: None,
                meta: Default::default(),
            });
        }
    }

    // Sort declarations by kind then name for readability
    declarations.sort_by(|a, b| {
        a.kind
            .to_string()
            .cmp(&b.kind.to_string())
            .then(a.name.cmp(&b.name))
    });

    // Build layers from discovered layer names
    let layers: Vec<Layer> = layers_seen
        .into_iter()
        .map(|name| Layer {
            name,
            depends: vec![],
        })
        .collect();

    Manifest {
        schema_version: "0.6".to_string(),
        name: name.to_string(),
        layers,
        type_aliases: vec![],
        custom_types: vec![],
        declarations,
        bindings: vec![],
        constraints: vec![],
        relations: vec![],
        meta: Default::default(),
    }
}

/// Run extraction and generate manifest, returning serialized JSON.
pub fn run(
    name: &str,
    config: &Config,
) -> Result<String, Box<dyn std::error::Error>> {
    let facts = extract::extract_all(config, None)?;
    let manifest = generate(name, &facts, config);
    let json = serde_json::to_string_pretty(&manifest)?;
    Ok(json)
}

//! P5: Suggest manifest patches from verification findings and source facts.
//!
//! Converts drift findings (T001-T004) into actionable manifest modifications:
//! - T001 (undeclared source type) → add declaration
//! - T002 (extra source field) → add field to existing declaration
//! - T003 (extra source method) → add op to existing declaration
//!
//! Output is a JSON array of patch operations.

use crate::config::Config;
use crate::extract::{FileFacts, TypeDefKind};
use plat_manifest::{DeclKind, Declaration, Field, Manifest, Op};

use std::collections::{HashMap, HashSet};

/// A suggested manifest patch operation.
#[derive(Debug)]
pub enum Suggestion {
    /// Add a new declaration to the manifest.
    AddDeclaration(Declaration),
    /// Add fields to an existing declaration.
    AddFields {
        declaration: String,
        fields: Vec<Field>,
    },
    /// Add ops to an existing declaration.
    AddOps {
        declaration: String,
        ops: Vec<Op>,
    },
}

/// Generate suggestions by comparing manifest against source facts.
pub fn suggest(
    manifest: &Manifest,
    facts: &[FileFacts],
    config: &Config,
) -> Vec<Suggestion> {
    let mut suggestions = Vec::new();

    let manifest_types: HashSet<String> = manifest
        .declarations
        .iter()
        .filter(|d| d.kind != DeclKind::Compose)
        .map(|d| plat_manifest::naming::convert(&d.name, config.type_case()))
        .collect();

    // Layer reverse map: file → layer
    let layer_map: HashMap<String, String> = facts
        .iter()
        .filter_map(|f| {
            f.layer.as_ref().map(|l| {
                (f.path.display().to_string(), l.clone())
            })
        })
        .collect();

    // T001: suggest adding undeclared source types
    for file in facts {
        for td in &file.types {
            if !manifest_types.contains(&td.name) {
                let kind = match td.kind {
                    TypeDefKind::Struct => DeclKind::Model,
                    TypeDefKind::Interface | TypeDefKind::Trait => DeclKind::Boundary,
                    TypeDefKind::Class => DeclKind::Model,
                    TypeDefKind::Enum => DeclKind::Model,
                };

                let fields: Vec<Field> = if kind == DeclKind::Model {
                    td.fields
                        .iter()
                        .map(|(n, t)| Field {
                            name: n.clone(),
                            typ: t.clone(),
                        })
                        .collect()
                } else {
                    vec![]
                };

                let ops: Vec<Op> = if kind == DeclKind::Boundary {
                    td.methods
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
                        .collect()
                } else {
                    vec![]
                };

                let layer = layer_map.get(&file.path.display().to_string()).cloned();

                suggestions.push(Suggestion::AddDeclaration(Declaration {
                    name: td.name.clone(),
                    kind,
                    layer,
                    paths: vec![file.path.display().to_string()],
                    fields,
                    ops,
                    inputs: vec![],
                    outputs: vec![],
                    needs: vec![],
                    implements: None,
                    injects: vec![],
                    entries: vec![],
                    service: None,
                    meta: Default::default(),
                }));
            }
        }
    }

    // T002: suggest adding extra fields
    for decl in &manifest.declarations {
        if decl.kind != DeclKind::Model {
            continue;
        }
        let type_name = plat_manifest::naming::convert(&decl.name, config.type_case());
        let td = facts
            .iter()
            .flat_map(|f| &f.types)
            .find(|t| t.name == type_name && t.kind == TypeDefKind::Struct);

        let Some(td) = td else { continue };

        let manifest_fields: HashSet<String> = decl
            .fields
            .iter()
            .map(|f| plat_manifest::naming::convert(&f.name, config.field_case()))
            .collect();

        let extra_fields: Vec<Field> = td
            .fields
            .iter()
            .filter(|(n, _)| !manifest_fields.contains(n.as_str()))
            .map(|(n, t)| Field {
                name: n.clone(),
                typ: t.clone(),
            })
            .collect();

        if !extra_fields.is_empty() {
            suggestions.push(Suggestion::AddFields {
                declaration: decl.name.clone(),
                fields: extra_fields,
            });
        }
    }

    // T003: suggest adding extra methods
    for decl in &manifest.declarations {
        if decl.kind != DeclKind::Boundary {
            continue;
        }
        let type_name = plat_manifest::naming::convert(&decl.name, config.type_case());
        let td = facts
            .iter()
            .flat_map(|f| &f.types)
            .find(|t| {
                t.name == type_name
                    && (t.kind == TypeDefKind::Interface || t.kind == TypeDefKind::Trait)
            });

        let Some(td) = td else { continue };

        let manifest_ops: HashSet<String> = decl
            .ops
            .iter()
            .map(|o| plat_manifest::naming::convert(&o.name, config.method_case()))
            .collect();

        let extra_ops: Vec<Op> = td
            .methods
            .iter()
            .filter(|m| !manifest_ops.contains(&m.name))
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

        if !extra_ops.is_empty() {
            suggestions.push(Suggestion::AddOps {
                declaration: decl.name.clone(),
                ops: extra_ops,
            });
        }
    }

    suggestions
}

/// Render suggestions as JSON.
pub fn render_json(suggestions: &[Suggestion]) -> String {
    let items: Vec<String> = suggestions
        .iter()
        .map(|s| match s {
            Suggestion::AddDeclaration(d) => {
                let fields_json = render_fields(&d.fields);
                let ops_json = render_ops(&d.ops);
                let layer = d
                    .layer
                    .as_deref()
                    .map(|l| format!("\"{}\"", l))
                    .unwrap_or_else(|| "null".to_string());
                let path = d.paths.first().map(|p| format!("\"{}\"", p)).unwrap_or_else(|| "null".to_string());
                format!(
                    concat!(
                        "    {{\n",
                        "      \"action\": \"add_declaration\",\n",
                        "      \"name\": \"{}\",\n",
                        "      \"kind\": \"{}\",\n",
                        "      \"layer\": {},\n",
                        "      \"path\": {},\n",
                        "      \"fields\": {},\n",
                        "      \"ops\": {}\n",
                        "    }}"
                    ),
                    d.name, d.kind, layer, path, fields_json, ops_json,
                )
            }
            Suggestion::AddFields { declaration, fields } => {
                let fields_json = render_fields(fields);
                format!(
                    concat!(
                        "    {{\n",
                        "      \"action\": \"add_fields\",\n",
                        "      \"declaration\": \"{}\",\n",
                        "      \"fields\": {}\n",
                        "    }}"
                    ),
                    declaration, fields_json,
                )
            }
            Suggestion::AddOps { declaration, ops } => {
                let ops_json = render_ops(ops);
                format!(
                    concat!(
                        "    {{\n",
                        "      \"action\": \"add_ops\",\n",
                        "      \"declaration\": \"{}\",\n",
                        "      \"ops\": {}\n",
                        "    }}"
                    ),
                    declaration, ops_json,
                )
            }
        })
        .collect();

    format!("{{\n  \"suggestions\": [\n{}\n  ]\n}}\n", items.join(",\n"))
}

fn render_fields(fields: &[Field]) -> String {
    if fields.is_empty() {
        return "[]".to_string();
    }
    let items: Vec<String> = fields
        .iter()
        .map(|f| format!("{{ \"name\": \"{}\", \"type\": \"{}\" }}", f.name, f.typ))
        .collect();
    format!("[{}]", items.join(", "))
}

fn render_ops(ops: &[Op]) -> String {
    if ops.is_empty() {
        return "[]".to_string();
    }
    let items: Vec<String> = ops
        .iter()
        .map(|o| {
            let inputs = render_fields(&o.inputs);
            let outputs = render_fields(&o.outputs);
            format!(
                "{{ \"name\": \"{}\", \"inputs\": {}, \"outputs\": {} }}",
                o.name, inputs, outputs
            )
        })
        .collect();
    format!("[{}]", items.join(", "))
}

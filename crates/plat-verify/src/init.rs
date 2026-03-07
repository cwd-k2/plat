//! P1: Reverse-engineer an initial manifest from source code.
//!
//! Extracts types from source using tree-sitter and generates a manifest
//! that reflects the current codebase structure. The output serves as a
//! starting point for iterative refinement (Reflexion Model bootstrapping).
//!
//! ## Heuristics
//!
//! Kind inference beyond syntactic category:
//!
//! - **Boundary**: interface (Go), trait (Rust), interface (TS) — direct from parser
//! - **Adapter**: struct/class that implements a boundary (explicit `implements` for
//!   TS/Rust, or method-set superset for Go structural typing)
//! - **Operation**: struct/class with fields referencing boundary types (dependency
//!   injection pattern)
//! - **Model**: everything else (structs with no boundary relationship)
//!
//! Relationship inference:
//! - `implements`: from adapter → boundary detection
//! - `needs`: from operation fields referencing boundaries
//! - Layer dependencies: from observed cross-layer references

use crate::config::Config;
use crate::extract::{self, FileFacts, TypeDef, TypeDefKind};
use plat_manifest::{
    Declaration, DeclKind, Field, Layer, Manifest, Op,
};

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};

/// Boundary info collected in the first pass.
struct BoundaryInfo {
    method_names: HashSet<String>,
    layer: Option<String>,
}

/// Generate an initial manifest from extracted source facts.
pub fn generate(
    name: &str,
    facts: &[FileFacts],
    config: &Config,
) -> Manifest {
    let mut layers_seen = BTreeSet::new();

    // Phase 1: Collect all boundaries with their method sets
    let mut boundaries: HashMap<String, BoundaryInfo> = HashMap::new();
    for file in facts {
        if let Some(ref layer) = file.layer {
            layers_seen.insert(layer.clone());
        }
        for td in &file.types {
            if matches!(td.kind, TypeDefKind::Interface | TypeDefKind::Trait) {
                let method_names: HashSet<String> =
                    td.methods.iter().map(|m| m.name.clone()).collect();
                boundaries.insert(td.name.clone(), BoundaryInfo {
                    method_names,
                    layer: file.layer.clone(),
                });
            }
        }
    }

    // Phase 2: Classify structs and collect declarations
    let mut declarations = Vec::new();

    for file in facts {
        for td in &file.types {
            let path = rel_path(file, config);

            match td.kind {
                TypeDefKind::Interface | TypeDefKind::Trait => {
                    declarations.push(make_boundary(td, file.layer.clone(), path));
                }
                TypeDefKind::Struct | TypeDefKind::Class | TypeDefKind::Enum => {
                    let classified = classify_struct(td, &boundaries);
                    declarations.push(make_declaration(
                        td,
                        classified,
                        file.layer.clone(),
                        path,
                    ));
                }
            }
        }
    }

    // Phase 3: Infer layer dependencies from declaration cross-references
    let layer_deps = infer_layer_deps(&declarations, &boundaries);

    // Sort declarations by kind then name for readability
    declarations.sort_by(|a, b| {
        a.kind
            .to_string()
            .cmp(&b.kind.to_string())
            .then(a.name.cmp(&b.name))
    });

    let layers: Vec<Layer> = layers_seen
        .into_iter()
        .map(|lname| Layer {
            name: lname.clone(),
            depends: layer_deps
                .get(&lname)
                .cloned()
                .unwrap_or_default()
                .into_iter()
                .collect(),
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

/// Classification result for a struct.
enum StructClass {
    /// Implements a boundary (adapter).
    Adapter { implements: String },
    /// Has boundary-typed fields (operation).
    Operation { needs: Vec<String> },
    /// Plain data (model).
    Model,
}

/// Classify a struct based on its relationships to known boundaries.
fn classify_struct(td: &TypeDef, boundaries: &HashMap<String, BoundaryInfo>) -> StructClass {
    // Check 1: Explicit implements (TypeScript/Rust)
    if !td.implements.is_empty() {
        if let Some(iface) = td.implements.first() {
            if boundaries.contains_key(iface) {
                return StructClass::Adapter { implements: iface.clone() };
            }
        }
    }

    // Check 2: Fields referencing boundary types → operation
    // (Checked before Go structural typing to avoid false adapter matches
    //  when a struct has both boundary-typed fields and a method that
    //  happens to satisfy a small interface like `Execute()`)
    let needs = find_boundary_refs(td, boundaries);
    if !needs.is_empty() {
        return StructClass::Operation { needs };
    }

    // Check 3: Go structural typing — method set is superset of some interface
    if !td.methods.is_empty() {
        let struct_methods: HashSet<String> =
            td.methods.iter().map(|m| m.name.clone()).collect();

        // Find the best-matching boundary (most methods matched)
        let mut best: Option<(&str, usize)> = None;
        for (bname, binfo) in boundaries {
            if binfo.method_names.is_empty() {
                continue;
            }
            if binfo.method_names.is_subset(&struct_methods) {
                let count = binfo.method_names.len();
                if best.map_or(true, |(_, c)| count > c) {
                    best = Some((bname.as_str(), count));
                }
            }
        }
        if let Some((bname, _)) = best {
            return StructClass::Adapter { implements: bname.to_string() };
        }
    }

    StructClass::Model
}

/// Find fields whose types reference known boundary names.
fn find_boundary_refs(td: &TypeDef, boundaries: &HashMap<String, BoundaryInfo>) -> Vec<String> {
    let mut needs = Vec::new();
    for (_, field_type) in &td.fields {
        // Extract base type name: "port.TaskRepository" → "TaskRepository", "*sql.DB" → "DB"
        let base = extract_base_type(field_type);
        if boundaries.contains_key(base) && !needs.contains(&base.to_string()) {
            needs.push(base.to_string());
        }
    }
    needs
}

/// Extract the base type name from a possibly qualified/decorated type string.
fn extract_base_type(t: &str) -> &str {
    let t = t.trim_start_matches('*').trim_start_matches('&');
    // "port.TaskRepository" → "TaskRepository"
    t.rsplit('.').next().unwrap_or(t)
}

/// Infer layer dependencies from cross-layer references.
fn infer_layer_deps(
    declarations: &[Declaration],
    boundaries: &HashMap<String, BoundaryInfo>,
) -> BTreeMap<String, BTreeSet<String>> {
    let mut deps: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();

    for decl in declarations {
        let Some(ref src_layer) = decl.layer else { continue };

        // needs → boundary's layer
        for need in &decl.needs {
            if let Some(binfo) = boundaries.get(need) {
                if let Some(ref tgt_layer) = binfo.layer {
                    if tgt_layer != src_layer {
                        deps.entry(src_layer.clone())
                            .or_default()
                            .insert(tgt_layer.clone());
                    }
                }
            }
        }

        // implements → boundary's layer
        if let Some(ref impl_name) = decl.implements {
            if let Some(binfo) = boundaries.get(impl_name) {
                if let Some(ref tgt_layer) = binfo.layer {
                    if tgt_layer != src_layer {
                        deps.entry(src_layer.clone())
                            .or_default()
                            .insert(tgt_layer.clone());
                    }
                }
            }
        }
    }

    deps
}

fn rel_path(file: &FileFacts, config: &Config) -> String {
    file.path
        .strip_prefix(&config.source.root)
        .map(|p| p.display().to_string())
        .unwrap_or_else(|_| file.path.display().to_string())
}

fn make_boundary(td: &TypeDef, layer: Option<String>, path: String) -> Declaration {
    let ops: Vec<Op> = td
        .methods
        .iter()
        .map(|m| Op {
            name: m.name.clone(),
            inputs: m
                .params
                .iter()
                .map(|(n, t)| Field { name: n.clone(), typ: t.clone() })
                .collect(),
            outputs: m
                .returns
                .iter()
                .map(|t| Field { name: String::new(), typ: t.clone() })
                .collect(),
        })
        .collect();

    Declaration {
        name: td.name.clone(),
        kind: DeclKind::Boundary,
        layer,
        paths: vec![path],
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

fn make_declaration(
    td: &TypeDef,
    class: StructClass,
    layer: Option<String>,
    path: String,
) -> Declaration {
    let fields: Vec<Field> = td
        .fields
        .iter()
        .map(|(n, t)| Field { name: n.clone(), typ: t.clone() })
        .collect();

    match class {
        StructClass::Adapter { implements } => Declaration {
            name: td.name.clone(),
            kind: DeclKind::Adapter,
            layer,
            paths: vec![path],
            fields: vec![],
            ops: vec![],
            inputs: vec![],
            outputs: vec![],
            needs: vec![],
            implements: Some(implements),
            injects: fields,
            entries: vec![],
            service: None,
            meta: Default::default(),
        },
        StructClass::Operation { needs } => Declaration {
            name: td.name.clone(),
            kind: DeclKind::Operation,
            layer,
            paths: vec![path],
            fields: vec![],
            ops: vec![],
            inputs: vec![],
            outputs: vec![],
            needs,
            implements: None,
            injects: vec![],
            entries: vec![],
            service: None,
            meta: Default::default(),
        },
        StructClass::Model => Declaration {
            name: td.name.clone(),
            kind: DeclKind::Model,
            layer,
            paths: vec![path],
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
        },
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

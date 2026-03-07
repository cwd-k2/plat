use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct Manifest {
    #[serde(default = "default_schema_version")]
    pub schema_version: String,
    #[serde(default)]
    pub name: String,
    pub layers: Vec<Layer>,
    #[serde(default)]
    pub type_aliases: Vec<TypeAlias>,
    #[serde(default)]
    pub custom_types: Vec<String>,
    pub declarations: Vec<Declaration>,
    #[serde(default)]
    pub bindings: Vec<Binding>,
    #[serde(default)]
    pub constraints: Vec<Constraint>,
    #[serde(default)]
    pub relations: Vec<Relation>,
    #[serde(default)]
    pub meta: HashMap<String, String>,
}

fn default_schema_version() -> String {
    "0.6".to_string()
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Layer {
    pub name: String,
    #[serde(default)]
    pub depends: Vec<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct TypeAlias {
    pub name: String,
    #[serde(rename = "type")]
    pub typ: String,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct Declaration {
    pub name: String,
    pub kind: DeclKind,
    pub layer: Option<String>,
    #[serde(default)]
    pub paths: Vec<String>,
    #[serde(default)]
    pub fields: Vec<Field>,
    #[serde(default)]
    pub ops: Vec<Op>,
    #[serde(default)]
    pub inputs: Vec<Field>,
    #[serde(default)]
    pub outputs: Vec<Field>,
    #[serde(default)]
    pub needs: Vec<String>,
    pub implements: Option<String>,
    #[serde(default)]
    pub injects: Vec<Field>,
    #[serde(default)]
    pub entries: Vec<String>,
    /// Service this declaration belongs to. None = shared across all services.
    #[serde(default)]
    pub service: Option<String>,
    #[serde(default)]
    pub meta: HashMap<String, String>,
}

#[derive(Debug, Default, Deserialize, Serialize, Clone, Copy, PartialEq, Eq, Hash)]
#[serde(rename_all = "lowercase")]
pub enum DeclKind {
    #[default]
    Model,
    Boundary,
    Operation,
    Adapter,
    Compose,
    #[serde(other)]
    Unknown,
}

impl std::fmt::Display for DeclKind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Model => write!(f, "model"),
            Self::Boundary => write!(f, "boundary"),
            Self::Operation => write!(f, "operation"),
            Self::Adapter => write!(f, "adapter"),
            Self::Compose => write!(f, "compose"),
            Self::Unknown => write!(f, "unknown"),
        }
    }
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Field {
    pub name: String,
    #[serde(rename = "type")]
    pub typ: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Op {
    pub name: String,
    #[serde(default)]
    pub inputs: Vec<Field>,
    #[serde(default)]
    pub outputs: Vec<Field>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Binding {
    pub boundary: String,
    pub adapter: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Constraint {
    pub name: String,
    pub description: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Relation {
    pub kind: String,
    pub source: String,
    pub target: String,
    #[serde(default)]
    pub meta: HashMap<String, String>,
}

impl Manifest {
    /// Split a multi-service manifest into per-service manifests.
    ///
    /// Declarations with `service: None` are included in all output manifests
    /// (shared types). Each output manifest is named `"{original}-{service}"`.
    /// Returns an empty vec if no declarations have a service tag.
    pub fn split_by_service(&self) -> Vec<Manifest> {
        let services: Vec<&str> = {
            let mut set = HashSet::new();
            for d in &self.declarations {
                if let Some(ref svc) = d.service {
                    set.insert(svc.as_str());
                }
            }
            let mut v: Vec<&str> = set.into_iter().collect();
            v.sort();
            v
        };

        if services.is_empty() {
            return Vec::new();
        }

        services
            .into_iter()
            .map(|svc| {
                let decls: Vec<Declaration> = self
                    .declarations
                    .iter()
                    .filter(|d| d.service.as_deref() == Some(svc) || d.service.is_none())
                    .cloned()
                    .collect();

                let decl_names: HashSet<&str> =
                    decls.iter().map(|d| d.name.as_str()).collect();

                Manifest {
                    schema_version: self.schema_version.clone(),
                    name: format!("{}-{}", self.name, svc),
                    layers: self.layers.clone(),
                    type_aliases: self.type_aliases.clone(),
                    custom_types: self.custom_types.clone(),
                    bindings: self
                        .bindings
                        .iter()
                        .filter(|b| {
                            decl_names.contains(b.boundary.as_str())
                                && decl_names.contains(b.adapter.as_str())
                        })
                        .cloned()
                        .collect(),
                    constraints: self.constraints.clone(),
                    relations: self
                        .relations
                        .iter()
                        .filter(|r| {
                            decl_names.contains(r.source.as_str())
                                || decl_names.contains(r.target.as_str())
                        })
                        .cloned()
                        .collect(),
                    meta: self.meta.clone(),
                    declarations: decls,
                }
            })
            .collect()
    }
}

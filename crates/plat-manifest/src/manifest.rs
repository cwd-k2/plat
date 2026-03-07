use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Deserialize, Serialize)]
pub struct Manifest {
    #[serde(default = "default_schema_version")]
    pub schema_version: String,
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

#[derive(Debug, Deserialize, Serialize)]
pub struct Layer {
    pub name: String,
    #[serde(default)]
    pub depends: Vec<String>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct TypeAlias {
    pub name: String,
    #[serde(rename = "type")]
    pub typ: String,
}

#[derive(Debug, Deserialize, Serialize)]
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
    #[serde(default)]
    pub meta: HashMap<String, String>,
}

#[derive(Debug, Deserialize, Serialize, Clone, Copy, PartialEq, Eq, Hash)]
#[serde(rename_all = "lowercase")]
pub enum DeclKind {
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

#[derive(Debug, Deserialize, Serialize)]
pub struct Field {
    pub name: String,
    #[serde(rename = "type")]
    pub typ: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Op {
    pub name: String,
    #[serde(default)]
    pub inputs: Vec<Field>,
    #[serde(default)]
    pub outputs: Vec<Field>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Binding {
    pub boundary: String,
    pub adapter: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Constraint {
    pub name: String,
    pub description: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Relation {
    pub kind: String,
    pub source: String,
    pub target: String,
    #[serde(default)]
    pub meta: HashMap<String, String>,
}

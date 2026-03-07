use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct Manifest {
    pub name: String,
    pub layers: Vec<Layer>,
    pub declarations: Vec<Declaration>,
    pub bindings: Vec<Binding>,
}

#[derive(Debug, Deserialize)]
pub struct Layer {
    pub name: String,
    pub depends: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub struct Declaration {
    pub name: String,
    pub kind: DeclKind,
    pub layer: Option<String>,
    #[serde(default)]
    pub fields: Vec<Field>,
    #[serde(default)]
    pub ops: Vec<Op>,
    #[serde(default)]
    pub needs: Vec<String>,
    pub implements: Option<String>,
    #[serde(default)]
    pub injects: Vec<Field>,
    #[serde(default)]
    #[allow(dead_code)]
    pub entries: Vec<String>,
}

#[derive(Debug, Deserialize, Clone, Copy, PartialEq, Eq, Hash)]
#[serde(rename_all = "lowercase")]
pub enum DeclKind {
    Model,
    Boundary,
    Operation,
    Adapter,
    Compose,
}

impl std::fmt::Display for DeclKind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Model => write!(f, "model"),
            Self::Boundary => write!(f, "boundary"),
            Self::Operation => write!(f, "operation"),
            Self::Adapter => write!(f, "adapter"),
            Self::Compose => write!(f, "compose"),
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct Field {
    pub name: String,
    #[serde(rename = "type")]
    pub typ: String,
}

#[derive(Debug, Deserialize)]
pub struct Op {
    pub name: String,
    pub inputs: Vec<Field>,
    pub outputs: Vec<Field>,
}

#[derive(Debug, Deserialize)]
pub struct Binding {
    pub boundary: String,
    pub adapter: String,
}

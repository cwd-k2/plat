use serde::Deserialize;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

// Re-export from plat-manifest so existing crate::config::{Language, Case} references work.
pub use plat_manifest::{Case, Language};

#[derive(Debug, Deserialize)]
pub struct Config {
    pub source: SourceConfig,
    #[serde(default)]
    pub types: HashMap<String, String>,
    #[serde(default)]
    pub naming: NamingConfig,
    #[serde(default)]
    pub checks: ChecksConfig,
}

#[derive(Debug, Deserialize)]
pub struct SourceConfig {
    pub language: Language,
    #[serde(default = "default_root")]
    pub root: PathBuf,
    #[serde(default)]
    pub layer_dirs: HashMap<String, String>,
    #[serde(default)]
    pub layer_match: LayerMatch,
}

/// How layer_dirs values are matched against file paths.
#[derive(Debug, Deserialize, Clone, Copy, PartialEq, Eq, Default)]
#[serde(rename_all = "lowercase")]
pub enum LayerMatch {
    #[default]
    Prefix,
    Component,
}

fn default_root() -> PathBuf {
    PathBuf::from("./src")
}

#[derive(Debug, Default, Deserialize)]
pub struct NamingConfig {
    pub type_case: Option<Case>,
    pub field_case: Option<Case>,
    pub method_case: Option<Case>,
}

#[derive(Debug, Deserialize)]
pub struct ChecksConfig {
    #[serde(default = "bool_true")]
    pub existence: bool,
    #[serde(default = "bool_true")]
    pub structure: bool,
    #[serde(default = "bool_true")]
    pub relation: bool,
    #[serde(default)]
    pub drift: bool,
    #[serde(default)]
    pub layer_deps: bool,
    #[serde(default)]
    pub imports: bool,
    #[serde(default)]
    pub naming: bool,
    #[serde(default)]
    pub severity: HashMap<String, Severity>,
}

impl Default for ChecksConfig {
    fn default() -> Self {
        Self {
            existence: true,
            structure: true,
            relation: true,
            drift: false,
            layer_deps: false,
            imports: false,
            naming: false,
            severity: HashMap::new(),
        }
    }
}

fn bool_true() -> bool {
    true
}

#[derive(Debug, Deserialize, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, clap::ValueEnum)]
#[serde(rename_all = "lowercase")]
pub enum Severity {
    Info,
    Warning,
    Error,
}

impl std::fmt::Display for Severity {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Info => write!(f, "info"),
            Self::Warning => write!(f, "warning"),
            Self::Error => write!(f, "error"),
        }
    }
}

impl Config {
    pub fn load(path: &Path) -> Result<Self, Box<dyn std::error::Error>> {
        let text = std::fs::read_to_string(path)?;
        let config: Config = toml::from_str(&text)?;
        Ok(config)
    }

    pub fn field_case(&self) -> Case {
        self.naming
            .field_case
            .unwrap_or_else(|| self.source.language.default_field_case())
    }

    pub fn method_case(&self) -> Case {
        self.naming
            .method_case
            .unwrap_or_else(|| self.source.language.default_method_case())
    }

    pub fn type_case(&self) -> Case {
        self.naming.type_case.unwrap_or(Case::Pascal)
    }

    pub fn severity_for(&self, code: &str) -> Option<Severity> {
        self.checks.severity.get(code).copied()
    }
}

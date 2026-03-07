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
    /// Path prefixes to exclude from scanning (relative to root).
    #[serde(default)]
    pub exclude: Vec<String>,
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

/// Multi-service configuration for cross-language verification.
#[derive(Debug, Deserialize)]
pub struct MultiServiceConfig {
    pub service: Vec<ServiceConfig>,
}

/// A single service in a multi-service configuration.
#[derive(Debug, Deserialize)]
pub struct ServiceConfig {
    pub name: String,
    pub language: Language,
    #[serde(default = "default_root")]
    pub root: PathBuf,
    #[serde(default)]
    pub layer_dirs: HashMap<String, String>,
    #[serde(default)]
    pub layer_match: LayerMatch,
    #[serde(default)]
    pub exclude: Vec<String>,
    #[serde(default)]
    pub types: HashMap<String, String>,
}

impl ServiceConfig {
    /// Convert a ServiceConfig into a full Config for single-service verification.
    pub fn to_config(&self) -> Config {
        Config {
            source: SourceConfig {
                language: self.language,
                root: self.root.clone(),
                layer_dirs: self.layer_dirs.clone(),
                layer_match: self.layer_match,
                exclude: self.exclude.clone(),
            },
            types: self.types.clone(),
            naming: NamingConfig::default(),
            checks: ChecksConfig::default(),
        }
    }
}

/// Configuration file format — either single-service or multi-service.
pub enum ConfigVariant {
    Single(Config),
    Multi(MultiServiceConfig),
}

impl ConfigVariant {
    pub fn load(path: &Path) -> Result<Self, Box<dyn std::error::Error>> {
        let text = std::fs::read_to_string(path)?;
        // Try multi-service first (has [[service]] array)
        if let Ok(multi) = toml::from_str::<MultiServiceConfig>(&text) {
            if !multi.service.is_empty() {
                return Ok(Self::Multi(multi));
            }
        }
        // Fall back to single-service
        let config: Config = toml::from_str(&text)?;
        Ok(Self::Single(config))
    }
}

impl Config {
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

    /// Convert a manifest name to source convention, respecting Go acronyms.
    pub fn convert_name(&self, name: &str, case: Case) -> String {
        if self.source.language == Language::Go && case == Case::Pascal {
            plat_manifest::naming::convert_go(name)
        } else {
            plat_manifest::naming::convert(name, case)
        }
    }

    pub fn convert_type_name(&self, name: &str) -> String {
        self.convert_name(name, self.type_case())
    }

    pub fn convert_field_name(&self, name: &str) -> String {
        self.convert_name(name, self.field_case())
    }

    pub fn convert_method_name(&self, name: &str) -> String {
        self.convert_name(name, self.method_case())
    }
}

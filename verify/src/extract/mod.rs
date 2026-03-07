pub mod go;

use std::path::{Path, PathBuf};

use crate::config::{Config, Language};

/// A type definition extracted from source code.
#[derive(Debug, Clone)]
pub struct TypeDef {
    pub name: String,
    pub kind: TypeDefKind,
    pub file: PathBuf,
    pub fields: Vec<(String, String)>,
    pub methods: Vec<MethodDef>,
    pub implements: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TypeDefKind {
    Struct,
    Interface,
    Trait,
    Class,
    Enum,
}

/// A method extracted from source code.
#[derive(Debug, Clone)]
pub struct MethodDef {
    pub name: String,
    pub params: Vec<(String, String)>,
    pub returns: Vec<String>,
}

/// All facts extracted from a source file.
#[derive(Debug, Clone)]
pub struct FileFacts {
    pub path: PathBuf,
    pub layer: Option<String>,
    pub types: Vec<TypeDef>,
}

/// Extract facts from all source files under the given root.
pub fn extract_all(config: &Config) -> Result<Vec<FileFacts>, Box<dyn std::error::Error>> {
    match config.source.language {
        Language::Go => go::extract(&config.source.root, &config.source.layer_dirs),
        Language::TypeScript => {
            eprintln!("warning: TypeScript extraction not yet implemented");
            Ok(Vec::new())
        }
        Language::Rust => {
            eprintln!("warning: Rust extraction not yet implemented");
            Ok(Vec::new())
        }
    }
}

/// Resolve which layer a file belongs to based on layer_dirs mapping.
pub fn resolve_layer(
    file: &Path,
    root: &Path,
    layer_dirs: &std::collections::HashMap<String, String>,
) -> Option<String> {
    let rel = file.strip_prefix(root).ok()?;
    let rel_str = rel.to_string_lossy();
    // Find the layer whose directory is a prefix of the relative path
    layer_dirs
        .iter()
        .filter(|(_, dir)| rel_str.starts_with(dir.as_str()))
        .max_by_key(|(_, dir)| dir.len())
        .map(|(layer, _)| layer.clone())
}

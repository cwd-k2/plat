pub mod go;
pub mod rust;
pub mod typescript;

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use walkdir::WalkDir;

use crate::cache::ExtractCache;
use crate::config::{Config, Language};

/// A type definition extracted from source code.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TypeDef {
    pub name: String,
    pub kind: TypeDefKind,
    pub file: PathBuf,
    pub fields: Vec<(String, String)>,
    pub methods: Vec<MethodDef>,
    pub implements: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TypeDefKind {
    Struct,
    Interface,
    Trait,
    Class,
    Enum,
}

/// A method extracted from source code.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MethodDef {
    pub name: String,
    pub params: Vec<(String, String)>,
    pub returns: Vec<String>,
}

/// All facts extracted from a source file.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileFacts {
    pub path: PathBuf,
    pub layer: Option<String>,
    pub types: Vec<TypeDef>,
}

/// Extract facts from all source files under the given root.
///
/// When `cache` is provided, previously parsed files whose mtime and size
/// have not changed are served from cache without re-parsing.
pub fn extract_all(
    config: &Config,
    mut cache: Option<&mut ExtractCache>,
) -> Result<Vec<FileFacts>, Box<dyn std::error::Error>> {
    let root = &config.source.root;
    let lang = config.source.language;
    let ext = lang.extension();
    let layer_dirs = &config.source.layer_dirs;

    let mut parser = match lang {
        Language::Go => go::new_parser()?,
        Language::TypeScript => typescript::new_parser()?,
        Language::Rust => rust::new_parser()?,
    };

    let mut facts = Vec::new();

    for entry in WalkDir::new(root).into_iter().filter_map(|e| e.ok()) {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        if path.extension().and_then(|e| e.to_str()) != Some(ext) {
            continue;
        }

        // Skip test files
        let is_test = match lang {
            Language::Go => go::is_test_file(path),
            Language::TypeScript => typescript::is_test_file(path),
            Language::Rust => rust::is_test_file(path, root),
        };
        if is_test {
            continue;
        }

        let meta = std::fs::metadata(path)?;

        // Try cache first
        let types = if let Some(ref cache) = cache {
            if let Some(cached) = cache.get(path, &meta) {
                cached
            } else {
                let source = std::fs::read_to_string(path)?;
                parse_source(lang, &mut parser, &source, path)
            }
        } else {
            let source = std::fs::read_to_string(path)?;
            parse_source(lang, &mut parser, &source, path)
        };

        // Update cache
        if let Some(ref mut cache) = cache {
            cache.put(path.to_path_buf(), &meta, types.clone());
        }

        if !types.is_empty() {
            let layer = resolve_layer(path, root, layer_dirs);
            facts.push(FileFacts {
                path: path.to_path_buf(),
                layer,
                types,
            });
        }
    }

    Ok(facts)
}

fn parse_source(
    lang: Language,
    parser: &mut tree_sitter::Parser,
    source: &str,
    path: &Path,
) -> Vec<TypeDef> {
    match lang {
        Language::Go => go::parse_file(parser, source, path),
        Language::TypeScript => typescript::parse_file(parser, source, path),
        Language::Rust => rust::parse_file(parser, source, path),
    }
}

/// Resolve which layer a file belongs to based on layer_dirs mapping.
pub fn resolve_layer(
    file: &Path,
    root: &Path,
    layer_dirs: &HashMap<String, String>,
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

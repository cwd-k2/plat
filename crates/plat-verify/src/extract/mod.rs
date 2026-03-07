pub mod go;
pub mod rust;
pub mod typescript;

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use walkdir::WalkDir;

use crate::cache::ExtractCache;
use crate::config::{Config, Language, LayerMatch};

/// Language-agnostic adapter for source code extraction.
///
/// Each supported language implements this trait, providing:
/// - Parser construction
/// - Test file detection
/// - Type/import extraction from source text
///
/// Adding a new language requires implementing this trait and
/// registering it in `adapter_for`.
pub trait LanguageAdapter {
    fn extension(&self) -> &'static str;
    fn is_test_file(&self, path: &Path, root: &Path) -> bool;
    fn parse_types(&self, parser: &mut tree_sitter::Parser, source: &str, file: &Path) -> Vec<TypeDef>;
    fn parse_imports(&self, parser: &mut tree_sitter::Parser, source: &str) -> Vec<String>;
    fn new_parser(&self) -> Result<tree_sitter::Parser, Box<dyn std::error::Error>>;
}

/// Create the appropriate adapter for a language.
pub fn adapter_for(lang: Language) -> Box<dyn LanguageAdapter> {
    match lang {
        Language::Go => Box::new(go::GoAdapter),
        Language::TypeScript => Box::new(typescript::TypeScriptAdapter),
        Language::Rust => Box::new(rust::RustAdapter),
    }
}

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
    #[serde(default)]
    pub imports: Vec<String>,
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
    let adapter = adapter_for(config.source.language);
    let ext = adapter.extension();
    let layer_dirs = &config.source.layer_dirs;

    let mut parser = adapter.new_parser()?;
    let mut facts = Vec::new();

    for entry in WalkDir::new(root).into_iter().filter_map(|e| e.ok()) {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        if path.extension().and_then(|e| e.to_str()) != Some(ext) {
            continue;
        }

        if adapter.is_test_file(path, root) {
            continue;
        }

        let meta = std::fs::metadata(path)?;

        // Try cache first
        let (types, imports) = if let Some(ref cache) = cache {
            if let Some(cached) = cache.get(path, &meta) {
                cached
            } else {
                let source = std::fs::read_to_string(path)?;
                let types = adapter.parse_types(&mut parser, &source, path);
                let imports = adapter.parse_imports(&mut parser, &source);
                (types, imports)
            }
        } else {
            let source = std::fs::read_to_string(path)?;
            let types = adapter.parse_types(&mut parser, &source, path);
            let imports = adapter.parse_imports(&mut parser, &source);
            (types, imports)
        };

        // Update cache
        if let Some(ref mut cache) = cache {
            cache.put(path.to_path_buf(), &meta, types.clone(), imports.clone());
        }

        if !types.is_empty() || !imports.is_empty() {
            let layer = resolve_layer(path, root, layer_dirs, config.source.layer_match);
            facts.push(FileFacts {
                path: path.to_path_buf(),
                layer,
                types,
                imports,
            });
        }
    }

    Ok(facts)
}

/// Resolve which layer a file belongs to based on layer_dirs mapping.
pub fn resolve_layer(
    file: &Path,
    root: &Path,
    layer_dirs: &HashMap<String, String>,
    layer_match: LayerMatch,
) -> Option<String> {
    let rel = file.strip_prefix(root).ok()?;
    let rel_str = rel.to_string_lossy();
    match layer_match {
        LayerMatch::Prefix => {
            layer_dirs
                .iter()
                .filter(|(_, dir)| rel_str.starts_with(dir.as_str()))
                .max_by_key(|(_, dir)| dir.len())
                .map(|(layer, _)| layer.clone())
        }
        LayerMatch::Component => {
            // Match layer_dirs values against any path component
            let components: Vec<&str> = rel.components()
                .filter_map(|c| c.as_os_str().to_str())
                .collect();
            layer_dirs
                .iter()
                .filter(|(_, dir)| components.contains(&dir.as_str()))
                .max_by_key(|(_, dir)| dir.len())
                .map(|(layer, _)| layer.clone())
        }
    }
}

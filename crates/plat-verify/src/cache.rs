use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

use serde::{Deserialize, Serialize};

use crate::extract::TypeDef;

/// Cache format version. Bump this when parser capabilities change
/// (e.g., adding enum extraction) to invalidate stale caches.
const CACHE_VERSION: u32 = 2;

/// Per-file cache entry keyed by mtime + size.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct CacheEntry {
    mtime_secs: u64,
    size: u64,
    types: Vec<TypeDef>,
    #[serde(default)]
    imports: Vec<String>,
}

/// File-level extraction cache backed by a JSON file.
#[derive(Debug, Serialize, Deserialize)]
pub struct ExtractCache {
    #[serde(default)]
    version: u32,
    entries: HashMap<PathBuf, CacheEntry>,
}

impl ExtractCache {
    /// Load cache from disk, or create empty if missing/corrupt/outdated.
    pub fn load(cache_path: &Path) -> Self {
        std::fs::read_to_string(cache_path)
            .ok()
            .and_then(|s| serde_json::from_str::<Self>(&s).ok())
            .filter(|c| c.version == CACHE_VERSION)
            .unwrap_or_else(|| Self {
                version: CACHE_VERSION,
                entries: HashMap::new(),
            })
    }

    /// Save cache to disk.
    pub fn save(&self, cache_path: &Path) -> Result<(), Box<dyn std::error::Error>> {
        if let Some(parent) = cache_path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let json = serde_json::to_string(self)?;
        std::fs::write(cache_path, json)?;
        Ok(())
    }

    /// Look up cached extraction result for a file. Returns `Some` if cache is fresh.
    pub fn get(&self, path: &Path, meta: &std::fs::Metadata) -> Option<(Vec<TypeDef>, Vec<String>)> {
        let entry = self.entries.get(path)?;
        let (mtime, size) = file_stamp(meta);
        if entry.mtime_secs == mtime && entry.size == size {
            Some((entry.types.clone(), entry.imports.clone()))
        } else {
            None
        }
    }

    /// Store extraction result for a file.
    pub fn put(&mut self, path: PathBuf, meta: &std::fs::Metadata, types: Vec<TypeDef>, imports: Vec<String>) {
        let (mtime, size) = file_stamp(meta);
        self.entries.insert(
            path,
            CacheEntry {
                mtime_secs: mtime,
                size,
                types,
                imports,
            },
        );
    }

    /// Remove entries for files that no longer exist on disk.
    pub fn prune(&mut self) {
        self.entries.retain(|path, _| path.exists());
    }
}

fn file_stamp(meta: &std::fs::Metadata) -> (u64, u64) {
    let mtime = meta
        .modified()
        .unwrap_or(SystemTime::UNIX_EPOCH)
        .duration_since(SystemTime::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let size = meta.len();
    (mtime, size)
}

/// Compute the cache file path for a given source root.
///
/// Uses a simple hash of the canonical root path to produce a unique
/// filename under the system temp directory.
pub fn cache_path_for(root: &Path) -> PathBuf {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};

    let canonical = root.canonicalize().unwrap_or_else(|_| root.to_path_buf());
    let mut hasher = DefaultHasher::new();
    canonical.hash(&mut hasher);
    let hash = hasher.finish();

    std::env::temp_dir()
        .join("plat-verify-cache")
        .join(format!("{:016x}.json", hash))
}

use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

use clap::Parser;
use plat_manifest::Language;
use plat_skeleton::{generate, Config};

#[derive(Parser)]
#[command(name = "plat-skeleton", about = "Generate code scaffolds from plat architecture manifest")]
struct Cli {
    /// Path to the manifest JSON file
    manifest: PathBuf,

    /// Target language: go, typescript, rust
    #[arg(short, long)]
    language: String,

    /// Output directory (default: current directory)
    #[arg(short, long, default_value = ".")]
    output: PathBuf,

    /// Layer name to directory mapping (repeatable, format: LAYER=DIR)
    #[arg(long = "layer-dir", value_name = "LAYER=DIR")]
    layer_dir: Vec<String>,

    /// Type mapping override (repeatable, format: TYPE=TYPE)
    #[arg(long = "type-map", value_name = "TYPE=TYPE")]
    type_map: Vec<String>,

    /// Go module path (Go only, for import paths)
    #[arg(long)]
    module: Option<String>,
}

fn parse_kv_pairs(pairs: &[String]) -> HashMap<String, String> {
    let mut map = HashMap::new();
    for pair in pairs {
        if let Some((k, v)) = pair.split_once('=') {
            map.insert(k.to_string(), v.to_string());
        }
    }
    map
}

fn main() {
    let cli = Cli::parse();

    let language = match cli.language.as_str() {
        "go" => Language::Go,
        "typescript" => Language::TypeScript,
        "rust" => Language::Rust,
        other => {
            eprintln!("Unknown language: {other}");
            std::process::exit(1);
        }
    };

    let layer_dirs = parse_kv_pairs(&cli.layer_dir);
    let user_types = parse_kv_pairs(&cli.type_map);

    let manifest_text = fs::read_to_string(&cli.manifest).unwrap_or_else(|e| {
        eprintln!("Failed to read manifest: {e}");
        std::process::exit(1);
    });
    let manifest: plat_manifest::Manifest =
        serde_json::from_str(&manifest_text).unwrap_or_else(|e| {
            eprintln!("Failed to parse manifest: {e}");
            std::process::exit(1);
        });

    let cfg = Config::new(language, layer_dirs, user_types, cli.module);

    let files = generate(&cfg, &manifest);

    for (path, content) in &files {
        let full = cli.output.join(path);
        if let Some(parent) = full.parent() {
            fs::create_dir_all(parent).unwrap_or_else(|e| {
                eprintln!("Failed to create directory {}: {e}", parent.display());
                std::process::exit(1);
            });
        }
        fs::write(&full, content).unwrap_or_else(|e| {
            eprintln!("Failed to write {}: {e}", full.display());
            std::process::exit(1);
        });
        println!("{}", full.display());
    }
}

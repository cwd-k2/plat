use std::collections::HashMap;
use std::path::PathBuf;
use std::process;

use clap::Parser;
use plat_manifest::Language;
use plat_contract::generate;

#[derive(Clone, Copy, clap::ValueEnum)]
enum Lang {
    Go,
    #[value(name = "typescript")]
    TypeScript,
    Rust,
}

impl Lang {
    fn into_language(self) -> Language {
        match self {
            Self::Go => Language::Go,
            Self::TypeScript => Language::TypeScript,
            Self::Rust => Language::Rust,
        }
    }
}

#[derive(Parser)]
#[command(
    name = "plat-contract",
    version,
    about = "Generate contract test skeletons from plat architecture manifest"
)]
struct Cli {
    /// Manifest JSON file path
    manifest: PathBuf,

    /// Target language: go, typescript, rust
    #[arg(short, long)]
    language: Lang,

    /// Output directory
    #[arg(short, long, default_value = ".")]
    output: PathBuf,

    /// Layer to directory mapping (repeatable, e.g. --layer-dir domain=src/domain)
    #[arg(long = "layer-dir", value_name = "LAYER=DIR")]
    layer_dir: Vec<String>,

    /// Type mapping override (repeatable, e.g. --type-map UUID=string)
    #[arg(long = "type-map", value_name = "TYPE=TYPE")]
    type_map: Vec<String>,
}

fn main() {
    let cli = Cli::parse();

    let manifest_text = match std::fs::read_to_string(&cli.manifest) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("error: cannot read manifest {}: {e}", cli.manifest.display());
            process::exit(2);
        }
    };
    let manifest: plat_manifest::Manifest = match serde_json::from_str(&manifest_text) {
        Ok(m) => m,
        Err(e) => {
            eprintln!("error: invalid manifest JSON: {e}");
            process::exit(2);
        }
    };

    let language = cli.language.into_language();
    let layer_dirs = parse_kv_pairs(&cli.layer_dir);
    let user_type_map = parse_kv_pairs(&cli.type_map);

    let files = generate(&manifest, language, &layer_dirs, &user_type_map);

    for (path, content) in &files {
        let full = cli.output.join(path);
        if let Some(parent) = full.parent() {
            if let Err(e) = std::fs::create_dir_all(parent) {
                eprintln!("error: cannot create directory {}: {e}", parent.display());
                process::exit(2);
            }
        }
        if let Err(e) = std::fs::write(&full, content) {
            eprintln!("error: cannot write {}: {e}", full.display());
            process::exit(2);
        }
        println!("  wrote {}", full.display());
    }

    println!("generated {} contract file(s)", files.len());
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

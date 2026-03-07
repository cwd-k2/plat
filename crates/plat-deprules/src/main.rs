use std::fs;
use std::process;

use clap::Parser;
use plat_deprules::{build_policy, parse_layer_dirs, render_depguard, render_eslint, render_matrix};

#[derive(Parser)]
#[command(name = "plat-deprules", about = "Generate linter dependency rules from plat manifest")]
struct Cli {
    /// Path to plat architecture manifest (JSON)
    manifest: String,

    /// Output format: depguard | eslint | matrix
    #[arg(short, long, default_value = "matrix")]
    format: String,

    /// Go module path (required for depguard format)
    #[arg(long)]
    module: Option<String>,

    /// Layer to directory mapping (repeatable), e.g. --layer-dir enterprise=domain
    #[arg(long = "layer-dir", value_name = "LAYER=DIR")]
    layer_dir: Vec<String>,
}

fn main() {
    let cli = Cli::parse();

    let content = fs::read_to_string(&cli.manifest).unwrap_or_else(|e| {
        eprintln!("error: cannot read {}: {e}", cli.manifest);
        process::exit(1);
    });

    let manifest: plat_manifest::Manifest = serde_json::from_str(&content).unwrap_or_else(|e| {
        eprintln!("error: invalid manifest: {e}");
        process::exit(1);
    });

    let policy = build_policy(&manifest);
    let dir_map = parse_layer_dirs(&cli.layer_dir);

    let output = match cli.format.as_str() {
        "matrix" => render_matrix(&policy),
        "depguard" => {
            let module = cli.module.as_deref().unwrap_or_else(|| {
                eprintln!("error: --module is required for depguard format");
                process::exit(1);
            });
            render_depguard(&policy, module, &dir_map)
        }
        "eslint" => render_eslint(&policy, &dir_map),
        other => {
            eprintln!("error: unknown format: {other} (expected: matrix, depguard, eslint)");
            process::exit(1);
        }
    };

    print!("{output}");
}

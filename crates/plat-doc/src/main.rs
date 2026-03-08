use std::path::PathBuf;

use clap::Parser;

#[derive(Parser)]
#[command(name = "plat-doc", version, about = "Generate documentation from plat manifest")]
struct Cli {
    /// Manifest JSON file path
    manifest: PathBuf,

    /// Output format
    #[arg(short, long, default_value = "markdown")]
    format: DocFormat,

    /// Mermaid graph direction
    #[arg(short, long, default_value = "lr")]
    direction: plat_doc::Direction,

    /// Mermaid subgraph grouping
    #[arg(short, long, default_value = "auto")]
    group: plat_doc::GroupMode,
}

#[derive(Clone, Copy, clap::ValueEnum)]
enum DocFormat {
    Markdown,
    Mermaid,
    Dsm,
}

fn main() {
    let cli = Cli::parse();

    let text = match std::fs::read_to_string(&cli.manifest) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("error: cannot read {}: {e}", cli.manifest.display());
            std::process::exit(2);
        }
    };

    let manifest: plat_manifest::Manifest = match serde_json::from_str(&text) {
        Ok(m) => m,
        Err(e) => {
            eprintln!("error: invalid manifest JSON: {e}");
            std::process::exit(2);
        }
    };

    let output = match cli.format {
        DocFormat::Markdown => plat_doc::render_markdown(&manifest),
        DocFormat::Mermaid => plat_doc::render_mermaid(&manifest, cli.direction, cli.group),
        DocFormat::Dsm => plat_doc::render_dsm(&manifest),
    };

    print!("{output}");
}

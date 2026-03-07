mod check;
mod config;
mod extract;
mod manifest;
mod naming;
mod report;
mod typemap;

use std::path::PathBuf;
use std::process;

use clap::Parser;

use config::{Config, Language, Severity};
use report::Format;

#[derive(Parser)]
#[command(name = "plat-verify", version, about = "Architecture conformance verification")]
struct Cli {
    /// Manifest JSON file path
    manifest: PathBuf,

    /// Config file path
    #[arg(short, long, default_value = "plat-verify.toml")]
    config: PathBuf,

    /// Source root directory (overrides config)
    #[arg(short, long)]
    root: Option<PathBuf>,

    /// Language (overrides config)
    #[arg(short, long)]
    language: Option<Language>,

    /// Output format
    #[arg(short, long, default_value = "text")]
    format: OutputFormat,

    /// Minimum severity to display
    #[arg(long, default_value = "info")]
    severity: Severity,

    /// Show only summary
    #[arg(short, long)]
    quiet: bool,
}

#[derive(Clone, Copy, clap::ValueEnum)]
enum OutputFormat {
    Text,
    Json,
}

fn main() {
    let cli = Cli::parse();

    // Load manifest
    let manifest_text = match std::fs::read_to_string(&cli.manifest) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("error: cannot read manifest {}: {e}", cli.manifest.display());
            process::exit(2);
        }
    };
    let manifest: manifest::Manifest = match serde_json::from_str(&manifest_text) {
        Ok(m) => m,
        Err(e) => {
            eprintln!("error: invalid manifest JSON: {e}");
            process::exit(2);
        }
    };

    // Load config
    let mut config = if cli.config.exists() {
        match Config::load(&cli.config) {
            Ok(c) => c,
            Err(e) => {
                eprintln!("error: cannot load config {}: {e}", cli.config.display());
                process::exit(2);
            }
        }
    } else if cli.language.is_some() {
        // No config file but language specified via CLI — use defaults
        Config {
            source: config::SourceConfig {
                language: cli.language.unwrap(),
                root: cli.root.clone().unwrap_or_else(|| PathBuf::from("./src")),
                layer_dirs: Default::default(),
            },
            types: Default::default(),
            naming: Default::default(),
            checks: Default::default(),
        }
    } else {
        eprintln!("error: no config file found and no --language specified");
        process::exit(2);
    };

    // CLI overrides
    if let Some(ref root) = cli.root {
        config.source.root = root.clone();
    }
    if let Some(lang) = cli.language {
        config.source.language = lang;
    }

    // Extract source facts
    let facts = match extract::extract_all(&config) {
        Ok(f) => f,
        Err(e) => {
            eprintln!("error: extraction failed: {e}");
            process::exit(2);
        }
    };

    // Run checks
    let mut findings = check::run_checks(&manifest, &facts, &config);

    // Filter by severity
    findings.retain(|f| f.severity >= cli.severity);

    // Report
    let summary = check::Summary::from_findings(&findings, manifest.declarations.len());
    let format = match cli.format {
        OutputFormat::Text => Format::Text,
        OutputFormat::Json => Format::Json,
    };

    if !cli.quiet {
        let output = report::render(
            &findings,
            &summary,
            &manifest.name,
            &config.source.language.to_string(),
            format,
        );
        print!("{output}");
    } else {
        println!(
            "{} error(s), {} warning(s), {} info",
            summary.errors, summary.warnings, summary.info
        );
    }

    // Exit code
    if summary.errors > 0 {
        process::exit(1);
    }
}

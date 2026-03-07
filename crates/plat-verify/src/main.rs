mod cache;
mod check;
mod config;
mod extract;
mod lsp;
mod report;

use std::path::PathBuf;
use std::process;
use std::sync::mpsc;
use std::time::{Duration, Instant};

use clap::Parser;
use notify::{RecursiveMode, Watcher};

use config::{Config, Language, Severity};
use report::Format;

#[derive(Clone, Copy, clap::ValueEnum)]
enum CliLanguage {
    Go,
    #[value(name = "typescript")]
    TypeScript,
    Rust,
}

impl From<CliLanguage> for Language {
    fn from(l: CliLanguage) -> Self {
        match l {
            CliLanguage::Go => Language::Go,
            CliLanguage::TypeScript => Language::TypeScript,
            CliLanguage::Rust => Language::Rust,
        }
    }
}

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
    language: Option<CliLanguage>,

    /// Output format
    #[arg(short, long, default_value = "text")]
    format: OutputFormat,

    /// Minimum severity to display
    #[arg(long, default_value = "info")]
    severity: Severity,

    /// Enable specific check categories (can be repeated; overrides config)
    #[arg(long = "check", value_name = "CATEGORY")]
    checks: Vec<CheckCategory>,

    /// Show only summary
    #[arg(short, long)]
    quiet: bool,

    /// Watch for file changes and re-verify
    #[arg(short, long)]
    watch: bool,

    /// Run as Language Server Protocol server over stdin/stdout
    #[arg(long)]
    lsp: bool,
}

#[derive(Clone, Copy, PartialEq, Eq, clap::ValueEnum)]
enum CheckCategory {
    Existence,
    Structure,
    Relation,
    Drift,
    #[value(name = "layer-deps")]
    LayerDeps,
    Imports,
    Naming,
}

#[derive(Clone, Copy, clap::ValueEnum)]
enum OutputFormat {
    Text,
    Json,
    /// LSP PublishDiagnosticsParams JSON array
    Lsp,
}

/// Parameters for a verification run, derived from CLI + config.
struct VerifyParams {
    manifest_path: PathBuf,
    config: Config,
    severity: Severity,
    format: Format,
    quiet: bool,
}

/// Run one verification cycle. Returns exit code (0 = ok, 1 = errors found, 2 = fatal).
fn verify_once(params: &VerifyParams) -> i32 {
    // Load manifest (re-read each time for watch mode)
    let manifest_text = match std::fs::read_to_string(&params.manifest_path) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("error: cannot read manifest {}: {e}", params.manifest_path.display());
            return 2;
        }
    };
    let manifest: plat_manifest::Manifest = match serde_json::from_str(&manifest_text) {
        Ok(m) => m,
        Err(e) => {
            eprintln!("error: invalid manifest JSON: {e}");
            return 2;
        }
    };

    // Extract source facts (with file-level cache)
    let cache_path = cache::cache_path_for(&params.config.source.root);
    let mut cache = cache::ExtractCache::load(&cache_path);
    let facts = match extract::extract_all(&params.config, Some(&mut cache)) {
        Ok(f) => f,
        Err(e) => {
            eprintln!("error: extraction failed: {e}");
            return 2;
        }
    };
    cache.prune();
    let _ = cache.save(&cache_path);

    // Run checks
    let mut findings = check::run_checks(&manifest, &facts, &params.config);
    findings.retain(|f| f.severity >= params.severity);

    // Compute convergence (Reflexion Model)
    let convergence = check::compute_convergence(&manifest, &facts, &params.config);

    // Report
    let summary = check::Summary::from_findings(&findings, manifest.declarations.len(), convergence);

    if !params.quiet {
        let output = report::render(
            &findings,
            &summary,
            &manifest.name,
            &params.config.source.language.to_string(),
            params.format,
        );
        print!("{output}");
    } else {
        println!(
            "{} error(s), {} warning(s), {} info",
            summary.errors, summary.warnings, summary.info
        );
    }

    if summary.errors > 0 { 1 } else { 0 }
}

fn main() {
    let cli = Cli::parse();

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
        Config {
            source: config::SourceConfig {
                language: Language::from(cli.language.unwrap()),
                root: cli.root.clone().unwrap_or_else(|| PathBuf::from("./src")),
                layer_dirs: Default::default(),
                layer_match: Default::default(),
                exclude: Default::default(),
            },
            types: Default::default(),
            naming: Default::default(),
            checks: Default::default(),
        }
    } else {
        eprintln!("error: no config file found and no --language specified");
        process::exit(2);
    };

    // Resolve root relative to config file directory (not CWD)
    if let Some(ref root) = cli.root {
        config.source.root = root.clone();
    } else if cli.config.exists() {
        if let Some(config_dir) = cli.config.parent() {
            if config.source.root.is_relative() {
                config.source.root = config_dir.join(&config.source.root);
            }
        }
    }
    if let Some(lang) = cli.language {
        config.source.language = Language::from(lang);
    }

    if !cli.checks.is_empty() {
        config.checks.existence = cli.checks.contains(&CheckCategory::Existence);
        config.checks.structure = cli.checks.contains(&CheckCategory::Structure);
        config.checks.relation = cli.checks.contains(&CheckCategory::Relation);
        config.checks.drift = cli.checks.contains(&CheckCategory::Drift);
        config.checks.layer_deps = cli.checks.contains(&CheckCategory::LayerDeps);
        config.checks.imports = cli.checks.contains(&CheckCategory::Imports);
        config.checks.naming = cli.checks.contains(&CheckCategory::Naming);
    }

    let format = match cli.format {
        OutputFormat::Text => Format::Text,
        OutputFormat::Json => Format::Json,
        OutputFormat::Lsp => Format::Lsp,
    };

    let params = VerifyParams {
        manifest_path: cli.manifest,
        config,
        severity: cli.severity,
        format,
        quiet: cli.quiet,
    };

    if cli.lsp {
        if let Err(e) = lsp::run(params.manifest_path, params.config) {
            eprintln!("LSP error: {e}");
            process::exit(2);
        }
    } else if cli.watch {
        run_watch(&params);
    } else {
        let code = verify_once(&params);
        process::exit(code);
    }
}

/// Watch mode: monitor source root + manifest for changes, re-run verification.
fn run_watch(params: &VerifyParams) -> ! {
    const DEBOUNCE: Duration = Duration::from_millis(300);

    eprintln!(
        "watching {} and {} for changes (Ctrl+C to stop)",
        params.config.source.root.display(),
        params.manifest_path.display(),
    );

    // Initial run
    let _ = verify_once(params);

    let (tx, rx) = mpsc::channel();
    let mut watcher = notify::recommended_watcher(move |res: notify::Result<notify::Event>| {
        if let Ok(event) = res {
            let dominated_by_non_file = event
                .paths
                .iter()
                .all(|p| p.is_dir() || p.extension().is_none());
            if !dominated_by_non_file {
                let _ = tx.send(());
            }
        }
    })
    .unwrap_or_else(|e| {
        eprintln!("error: cannot create file watcher: {e}");
        process::exit(2);
    });

    // Watch source root
    if let Err(e) = watcher.watch(&params.config.source.root, RecursiveMode::Recursive) {
        eprintln!(
            "error: cannot watch {}: {e}",
            params.config.source.root.display()
        );
        process::exit(2);
    }

    // Watch manifest file
    if let Err(e) = watcher.watch(&params.manifest_path, RecursiveMode::NonRecursive) {
        eprintln!(
            "error: cannot watch {}: {e}",
            params.manifest_path.display()
        );
        process::exit(2);
    }

    loop {
        // Wait for first event
        let _ = rx.recv();

        // Debounce: drain further events within the window
        let deadline = Instant::now() + DEBOUNCE;
        while Instant::now() < deadline {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if rx.recv_timeout(remaining).is_err() {
                break;
            }
        }

        eprintln!("\n--- re-verifying ---\n");
        let _ = verify_once(params);
    }
}

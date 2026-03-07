mod cache;
mod check;
mod config;
mod contracts;
mod extract;
mod init;
mod lsp;
mod report;
mod suggest;

use std::path::PathBuf;
use std::process;
use std::sync::mpsc;
use std::time::{Duration, Instant};

use clap::Parser;
use notify::{RecursiveMode, Watcher};

use config::{Config, ConfigVariant, Language, Severity};
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
    /// Manifest JSON file path (not required for --init)
    manifest: Option<PathBuf>,

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

    /// Suggest manifest patches from drift findings (T001-T003)
    #[arg(long)]
    suggest: bool,

    /// Compare manifests for contract compatibility (provider manifest path)
    #[arg(long = "contracts", value_name = "PROVIDER_MANIFEST")]
    contracts: Option<PathBuf>,

    /// Generate initial manifest from source code (reverse engineering)
    #[arg(long)]
    init: bool,

    /// Architecture name for --init output
    #[arg(long, default_value = "my-service")]
    name: String,
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
    suggest: bool,
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

    // --suggest mode: output manifest patch suggestions
    if params.suggest {
        let suggestions = suggest::suggest(&manifest, &facts, &params.config);
        let output = suggest::render_json(&suggestions);
        print!("{output}");
        return 0;
    }

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

    let format = match cli.format {
        OutputFormat::Text => Format::Text,
        OutputFormat::Json => Format::Json,
        OutputFormat::Lsp => Format::Lsp,
    };

    let config_dir = cli.config.parent().map(|p| p.to_path_buf());

    // --contracts mode: manifest-to-manifest comparison (no source code)
    if let Some(ref provider_path) = cli.contracts {
        let manifest_path = cli.manifest.unwrap_or_else(|| {
            eprintln!("error: --contracts requires a consumer manifest as positional argument");
            process::exit(2);
        });
        let code = run_contracts(&manifest_path, provider_path, format);
        process::exit(code);
    }

    // --init mode: generate manifest from source (no manifest needed)
    if cli.init {
        let config = load_config_or_cli(&cli, config_dir.as_deref());
        let code = run_init(&cli.name, &config);
        process::exit(code);
    }

    // All other modes require a manifest
    let manifest_path = cli.manifest.clone().unwrap_or_else(|| {
        eprintln!("error: manifest path required (use --init to generate one)");
        process::exit(2);
    });
    let cli_with_manifest = CliWithManifest { cli, manifest_path };

    // Try loading config — detect multi-service vs single-service
    if cli_with_manifest.cli.config.exists() {
        match ConfigVariant::load(&cli_with_manifest.cli.config) {
            Ok(ConfigVariant::Multi(multi)) => {
                let code = verify_multi(
                    &cli_with_manifest.manifest_path,
                    &multi.service,
                    config_dir.as_deref(),
                    cli_with_manifest.cli.severity,
                    format,
                    cli_with_manifest.cli.quiet,
                );
                process::exit(code);
            }
            Ok(ConfigVariant::Single(config)) => {
                let config = apply_cli_overrides(config, &cli_with_manifest.cli, config_dir.as_deref());
                run_single(cli_with_manifest, config, format);
            }
            Err(e) => {
                eprintln!("error: cannot load config {}: {e}", cli_with_manifest.cli.config.display());
                process::exit(2);
            }
        }
    } else if cli_with_manifest.cli.language.is_some() {
        let config = Config {
            source: config::SourceConfig {
                language: Language::from(cli_with_manifest.cli.language.unwrap()),
                root: cli_with_manifest.cli.root.clone().unwrap_or_else(|| PathBuf::from("./src")),
                layer_dirs: Default::default(),
                layer_match: Default::default(),
                exclude: Default::default(),
            },
            types: Default::default(),
            naming: Default::default(),
            checks: Default::default(),
        };
        run_single(cli_with_manifest, config, format);
    } else {
        eprintln!("error: no config file found and no --language specified");
        process::exit(2);
    }
}

/// Helper struct: CLI with resolved manifest path.
struct CliWithManifest {
    cli: Cli,
    manifest_path: PathBuf,
}

/// Load config from file or construct from CLI flags.
fn load_config_or_cli(cli: &Cli, config_dir: Option<&std::path::Path>) -> Config {
    if cli.config.exists() {
        match ConfigVariant::load(&cli.config) {
            Ok(ConfigVariant::Single(config)) => {
                return apply_cli_overrides(config, cli, config_dir);
            }
            Ok(ConfigVariant::Multi(multi)) => {
                if let Some(svc) = multi.service.first() {
                    let mut config = svc.to_config();
                    if let Some(dir) = config_dir {
                        if config.source.root.is_relative() {
                            config.source.root = dir.join(&config.source.root);
                        }
                    }
                    return config;
                }
            }
            Err(_) => {}
        }
    }
    if let Some(lang) = cli.language {
        Config {
            source: config::SourceConfig {
                language: Language::from(lang),
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
    }
}

/// Run --contracts mode.
fn run_contracts(consumer_path: &PathBuf, provider_path: &PathBuf, format: Format) -> i32 {
    let load = |path: &PathBuf| -> Result<plat_manifest::Manifest, String> {
        let text = std::fs::read_to_string(path)
            .map_err(|e| format!("cannot read {}: {e}", path.display()))?;
        serde_json::from_str(&text)
            .map_err(|e| format!("invalid JSON in {}: {e}", path.display()))
    };

    let consumer = match load(consumer_path) {
        Ok(m) => m,
        Err(e) => { eprintln!("error: {e}"); return 2; }
    };
    let provider = match load(provider_path) {
        Ok(m) => m,
        Err(e) => { eprintln!("error: {e}"); return 2; }
    };

    let findings = contracts::check(&consumer, &provider);
    let output = match format {
        Format::Json => contracts::render_json(&findings, &consumer.name, &provider.name),
        _ => contracts::render_text(&findings, &consumer.name, &provider.name),
    };
    print!("{output}");

    let errors = findings.iter().filter(|f| f.severity == Severity::Error).count();
    if errors > 0 { 1 } else { 0 }
}

/// Run --init mode.
fn run_init(name: &str, config: &Config) -> i32 {
    match init::run(name, config) {
        Ok(json) => {
            println!("{json}");
            0
        }
        Err(e) => {
            eprintln!("error: {e}");
            2
        }
    }
}

fn apply_cli_overrides(mut config: Config, cli: &Cli, config_dir: Option<&std::path::Path>) -> Config {
    if let Some(ref root) = cli.root {
        config.source.root = root.clone();
    } else if let Some(dir) = config_dir {
        if config.source.root.is_relative() {
            config.source.root = dir.join(&config.source.root);
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
    config
}

fn run_single(cwm: CliWithManifest, config: Config, format: Format) {
    let params = VerifyParams {
        manifest_path: cwm.manifest_path,
        config,
        severity: cwm.cli.severity,
        format,
        quiet: cwm.cli.quiet,
        suggest: cwm.cli.suggest,
    };

    if cwm.cli.lsp {
        if let Err(e) = lsp::run(params.manifest_path, params.config) {
            eprintln!("LSP error: {e}");
            process::exit(2);
        }
    } else if cwm.cli.watch {
        run_watch(&params);
    } else {
        let code = verify_once(&params);
        process::exit(code);
    }
}

/// Filter manifest declarations for a specific service.
///
/// A declaration belongs to a service if:
/// - Its `service` field matches the service name, OR
/// - Its `service` field is None (shared across all services)
fn filter_manifest_for_service(manifest: &plat_manifest::Manifest, service_name: &str) -> plat_manifest::Manifest {
    let declarations: Vec<_> = manifest.declarations.iter()
        .filter(|d| {
            d.service.as_ref().map_or(true, |s| s == service_name)
        })
        .cloned()
        .collect();

    let decl_names: std::collections::HashSet<&str> = declarations.iter()
        .map(|d| d.name.as_str())
        .collect();

    let bindings: Vec<_> = manifest.bindings.iter()
        .filter(|b| decl_names.contains(b.adapter.as_str()) && decl_names.contains(b.boundary.as_str()))
        .cloned()
        .collect();

    plat_manifest::Manifest {
        schema_version: manifest.schema_version.clone(),
        name: manifest.name.clone(),
        layers: manifest.layers.clone(),
        type_aliases: manifest.type_aliases.clone(),
        custom_types: manifest.custom_types.clone(),
        declarations,
        bindings,
        constraints: manifest.constraints.clone(),
        relations: manifest.relations.clone(),
        meta: manifest.meta.clone(),
    }
}

/// Run multi-service verification. Returns exit code.
fn verify_multi(
    manifest_path: &PathBuf,
    services: &[config::ServiceConfig],
    config_dir: Option<&std::path::Path>,
    severity: Severity,
    format: Format,
    quiet: bool,
) -> i32 {
    let manifest_text = match std::fs::read_to_string(manifest_path) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("error: cannot read manifest {}: {e}", manifest_path.display());
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

    let mut total_errors = 0;

    for svc in services {
        let mut config = svc.to_config();

        // Resolve root relative to config file directory
        if let Some(dir) = config_dir {
            if config.source.root.is_relative() {
                config.source.root = dir.join(&config.source.root);
            }
        }

        let svc_manifest = filter_manifest_for_service(&manifest, &svc.name);

        let cache_path = cache::cache_path_for(&config.source.root);
        let mut cache = cache::ExtractCache::load(&cache_path);
        let facts = match extract::extract_all(&config, Some(&mut cache)) {
            Ok(f) => f,
            Err(e) => {
                eprintln!("error: extraction failed for service {}: {e}", svc.name);
                total_errors += 1;
                continue;
            }
        };
        cache.prune();
        let _ = cache.save(&cache_path);

        let mut findings = check::run_checks(&svc_manifest, &facts, &config);
        findings.retain(|f| f.severity >= severity);

        let convergence = check::compute_convergence(&svc_manifest, &facts, &config);
        let summary = check::Summary::from_findings(
            &findings,
            svc_manifest.declarations.len(),
            convergence,
        );

        if !quiet {
            let svc_label = format!("{} [{}]", manifest.name, svc.name);
            let output = report::render(
                &findings,
                &summary,
                &svc_label,
                &config.source.language.to_string(),
                format,
            );
            print!("{output}");
            if services.len() > 1 {
                println!();
            }
        } else {
            println!(
                "[{}] {} error(s), {} warning(s), {} info",
                svc.name, summary.errors, summary.warnings, summary.info
            );
        }

        if summary.errors > 0 {
            total_errors += 1;
        }
    }

    if total_errors > 0 { 1 } else { 0 }
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

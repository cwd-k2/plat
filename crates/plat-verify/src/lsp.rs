use std::path::PathBuf;

use lsp_server::{Connection, Message, Notification};
use lsp_types::notification::{DidSaveTextDocument, PublishDiagnostics};
use lsp_types::*;

use crate::cache;
use crate::check;
use crate::config::Config;
use crate::extract;

/// Run plat-verify as an LSP server over stdin/stdout.
///
/// Publishes diagnostics on `textDocument/didSave` notifications.
/// Requires a manifest path and config to be provided at startup.
pub fn run(manifest_path: PathBuf, config: Config) -> Result<(), Box<dyn std::error::Error>> {
    let (connection, io_threads) = Connection::stdio();

    // Initialize
    let server_capabilities = ServerCapabilities {
        text_document_sync: Some(TextDocumentSyncCapability::Options(
            TextDocumentSyncOptions {
                open_close: Some(true),
                save: Some(TextDocumentSyncSaveOptions::SaveOptions(SaveOptions {
                    include_text: Some(false),
                })),
                ..Default::default()
            },
        )),
        ..Default::default()
    };

    let init_params = connection.initialize(serde_json::to_value(server_capabilities)?)?;
    let _init: InitializeParams = serde_json::from_value(init_params)?;

    // Publish initial diagnostics
    publish_all(&connection, &manifest_path, &config);

    // Main loop
    for msg in &connection.receiver {
        match msg {
            Message::Notification(not) => {
                if not.method == <DidSaveTextDocument as lsp_types::notification::Notification>::METHOD {
                    publish_all(&connection, &manifest_path, &config);
                }
                if not.method == "exit" {
                    break;
                }
            }
            Message::Request(req) => {
                if connection.handle_shutdown(&req)? {
                    break;
                }
            }
            Message::Response(_) => {}
        }
    }

    io_threads.join()?;
    Ok(())
}

/// Run the full verification pipeline and publish diagnostics to the client.
fn publish_all(connection: &Connection, manifest_path: &PathBuf, config: &Config) {
    let findings = run_verify(manifest_path, config);

    // Group findings by file URI
    let mut by_uri: std::collections::HashMap<String, Vec<Diagnostic>> =
        std::collections::HashMap::new();

    let manifest_uri = format!(
        "file://{}",
        manifest_path
            .canonicalize()
            .unwrap_or_else(|_| manifest_path.clone())
            .display()
    );

    for f in &findings {
        let uri = f
            .source_file
            .as_ref()
            .and_then(|p| {
                let abs = std::path::Path::new(p);
                let full = if abs.is_absolute() {
                    abs.to_path_buf()
                } else {
                    abs.canonicalize().unwrap_or_else(|_| abs.to_path_buf())
                };
                Some(format!("file://{}", full.display()))
            })
            .unwrap_or_else(|| manifest_uri.clone());

        let line = f.source_line.map(|l| l.saturating_sub(1) as u32).unwrap_or(0);
        let severity = match f.severity {
            crate::config::Severity::Error => Some(DiagnosticSeverity::ERROR),
            crate::config::Severity::Warning => Some(DiagnosticSeverity::WARNING),
            crate::config::Severity::Info => Some(DiagnosticSeverity::INFORMATION),
        };

        let diag = Diagnostic {
            range: Range {
                start: Position { line, character: 0 },
                end: Position { line, character: 0 },
            },
            severity,
            code: Some(NumberOrString::String(f.code.clone())),
            source: Some("plat-verify".to_string()),
            message: format!("[{}] {}", f.declaration, f.message),
            ..Default::default()
        };

        by_uri.entry(uri).or_default().push(diag);
    }

    // Publish diagnostics per file
    for (uri_str, diagnostics) in by_uri {
        let Ok(uri) = uri_str.parse::<Uri>() else {
            continue;
        };
        let params = PublishDiagnosticsParams {
            uri,
            diagnostics,
            version: None,
        };
        let not = Notification::new(
            <PublishDiagnostics as lsp_types::notification::Notification>::METHOD.to_string(),
            params,
        );
        let _ = connection.sender.send(Message::Notification(not));
    }
}

/// Run verification pipeline, returning findings.
fn run_verify(manifest_path: &PathBuf, config: &Config) -> Vec<check::Finding> {
    let manifest_text = match std::fs::read_to_string(manifest_path) {
        Ok(t) => t,
        Err(_) => return Vec::new(),
    };
    let manifest: plat_manifest::Manifest = match serde_json::from_str(&manifest_text) {
        Ok(m) => m,
        Err(_) => return Vec::new(),
    };

    let cache_path = cache::cache_path_for(&config.source.root);
    let mut cache = cache::ExtractCache::load(&cache_path);
    let facts = match extract::extract_all(config, Some(&mut cache)) {
        Ok(f) => f,
        Err(_) => return Vec::new(),
    };
    cache.prune();
    let _ = cache.save(&cache_path);

    check::run_checks(&manifest, &facts, config)
}

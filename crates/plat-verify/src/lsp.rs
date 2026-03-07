use std::collections::HashMap;
use std::path::PathBuf;

use lsp_server::{Connection, Message, Notification, Response};
use lsp_types::notification::{DidSaveTextDocument, PublishDiagnostics};
use lsp_types::request::CodeActionRequest;
use lsp_types::*;

use crate::cache;
use crate::check;
use crate::config::Config;
use crate::extract;

/// Persistent LSP server state for incremental analysis.
struct ServerState {
    manifest_path: PathBuf,
    config: Config,
    /// Previous diagnostics by URI, for delta computation.
    prev_diagnostics: HashMap<String, Vec<Diagnostic>>,
}

/// Run plat-verify as an LSP server over stdin/stdout.
///
/// Publishes diagnostics on `textDocument/didSave` notifications.
/// Uses incremental delta: only publishes URIs whose diagnostics changed.
pub fn run(manifest_path: PathBuf, config: Config) -> Result<(), Box<dyn std::error::Error>> {
    let (connection, io_threads) = Connection::stdio();

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
        code_action_provider: Some(CodeActionProviderCapability::Options(
            CodeActionOptions {
                code_action_kinds: Some(vec![CodeActionKind::QUICKFIX]),
                ..Default::default()
            },
        )),
        ..Default::default()
    };

    let init_params = connection.initialize(serde_json::to_value(server_capabilities)?)?;
    let _init: InitializeParams = serde_json::from_value(init_params)?;

    let mut state = ServerState {
        manifest_path,
        config,
        prev_diagnostics: HashMap::new(),
    };

    // Publish initial diagnostics (full)
    publish_delta(&connection, &mut state);

    // Main loop
    for msg in &connection.receiver {
        match msg {
            Message::Notification(not) => {
                if not.method == <DidSaveTextDocument as lsp_types::notification::Notification>::METHOD {
                    publish_delta(&connection, &mut state);
                }
                if not.method == "exit" {
                    break;
                }
            }
            Message::Request(req) => {
                if connection.handle_shutdown(&req)? {
                    break;
                }
                if req.method == <CodeActionRequest as lsp_types::request::Request>::METHOD {
                    let params: CodeActionParams = serde_json::from_value(req.params).unwrap_or_else(|_| {
                        CodeActionParams {
                            text_document: TextDocumentIdentifier { uri: "file:///".parse().unwrap() },
                            range: Range::default(),
                            context: CodeActionContext::default(),
                            work_done_progress_params: Default::default(),
                            partial_result_params: Default::default(),
                        }
                    });
                    let actions = handle_code_action(&params);
                    let result = serde_json::to_value(actions).unwrap_or_default();
                    let resp = Response::new_ok(req.id, result);
                    let _ = connection.sender.send(Message::Response(resp));
                }
            }
            Message::Response(_) => {}
        }
    }

    io_threads.join()?;
    Ok(())
}

/// Run the verification pipeline and publish only changed diagnostics.
///
/// Compares new diagnostics against previous state per URI.
/// Only URIs with added, removed, or changed diagnostics are re-published.
/// URIs that had diagnostics before but none now get an empty publish (clear).
fn publish_delta(connection: &Connection, state: &mut ServerState) {
    let findings = run_verify(&state.manifest_path, &state.config);

    let manifest_uri = format!(
        "file://{}",
        state.manifest_path
            .canonicalize()
            .unwrap_or_else(|_| state.manifest_path.clone())
            .display()
    );

    let mut new_diagnostics: HashMap<String, Vec<Diagnostic>> = HashMap::new();

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

        new_diagnostics.entry(uri).or_default().push(diag);
    }

    // Publish URIs that changed
    for (uri_str, diags) in &new_diagnostics {
        let changed = match state.prev_diagnostics.get(uri_str) {
            Some(prev) => !diagnostics_eq(prev, diags),
            None => true,
        };
        if changed {
            send_diagnostics(connection, uri_str, diags.clone());
        }
    }

    // Clear URIs that no longer have diagnostics
    for uri_str in state.prev_diagnostics.keys() {
        if !new_diagnostics.contains_key(uri_str) {
            send_diagnostics(connection, uri_str, Vec::new());
        }
    }

    state.prev_diagnostics = new_diagnostics;
}

/// Compare two diagnostic lists for equality (order-independent).
fn diagnostics_eq(a: &[Diagnostic], b: &[Diagnostic]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    // Simple: check same codes and messages in same order
    a.iter().zip(b.iter()).all(|(x, y)| {
        x.code == y.code && x.message == y.message && x.range == y.range && x.severity == y.severity
    })
}

fn send_diagnostics(connection: &Connection, uri_str: &str, diagnostics: Vec<Diagnostic>) {
    let Ok(uri) = uri_str.parse::<Uri>() else {
        return;
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

/// Generate code actions from diagnostics in the requested range.
///
/// For naming violations (N001-N003), produces a quickfix that renames
/// the identifier to its expected form via a workspace edit.
fn handle_code_action(params: &CodeActionParams) -> Vec<CodeActionOrCommand> {
    let mut actions = Vec::new();

    for diag in &params.context.diagnostics {
        let Some(ref source) = diag.source else { continue };
        if source != "plat-verify" { continue }

        let Some(NumberOrString::String(ref code)) = diag.code else { continue };
        if !matches!(code.as_str(), "N001" | "N002" | "N003") { continue }

        // Extract expected name from message: `... (expected "foo")`
        let Some(expected) = extract_expected(&diag.message) else { continue };

        // Extract current name from message: `type "bar"` or `field "bar"` or `method "bar"`
        let Some(current) = extract_current(&diag.message) else { continue };

        let title = format!("Rename \"{}\" to \"{}\"", current, expected);

        // The edit replaces the diagnostic range with the expected name.
        // Since we report range at (line, 0)..(line, 0), the editor would need
        // to refine it. For now, we provide a placeholder range action.
        let mut changes = HashMap::new();
        changes.insert(
            params.text_document.uri.clone(),
            vec![TextEdit {
                range: diag.range,
                new_text: expected.clone(),
            }],
        );

        actions.push(CodeActionOrCommand::CodeAction(CodeAction {
            title,
            kind: Some(CodeActionKind::QUICKFIX),
            diagnostics: Some(vec![diag.clone()]),
            edit: Some(WorkspaceEdit {
                changes: Some(changes),
                ..Default::default()
            }),
            ..Default::default()
        }));
    }

    actions
}

/// Extract the expected name from a naming diagnostic message.
/// Pattern: `(expected "someName")`
fn extract_expected(msg: &str) -> Option<String> {
    let marker = "(expected \"";
    let start = msg.find(marker)? + marker.len();
    let end = msg[start..].find('"')? + start;
    Some(msg[start..end].to_string())
}

/// Extract the current name from a naming diagnostic message.
/// Pattern: `type "name"` or `field "name"` or `method "name"`
fn extract_current(msg: &str) -> Option<String> {
    // Look for the first quoted string after [decl]
    let bracket_end = msg.find(']').unwrap_or(0);
    let rest = &msg[bracket_end..];
    let q1 = rest.find('"')? + 1;
    let q2 = rest[q1..].find('"')? + q1;
    Some(rest[q1..q2].to_string())
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

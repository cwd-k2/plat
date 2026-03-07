use crate::check::Finding;
use crate::config::Severity;
use std::collections::BTreeMap;

/// Render findings as a JSON array of LSP `PublishDiagnosticsParams` objects.
///
/// Groups findings by file URI. Findings without a source file are grouped
/// under the manifest URI placeholder `"file:///plat-manifest"`.
pub fn render(findings: &[Finding]) -> String {
    // Group findings by file
    let mut by_file: BTreeMap<String, Vec<&Finding>> = BTreeMap::new();
    for f in findings {
        let uri = f
            .source_file
            .as_ref()
            .map(|p| file_uri(p))
            .unwrap_or_else(|| "file:///plat-manifest".to_string());
        by_file.entry(uri).or_default().push(f);
    }

    let entries: Vec<String> = by_file
        .iter()
        .map(|(uri, file_findings)| {
            let diags: Vec<String> = file_findings
                .iter()
                .map(|f| {
                    let line = f.source_line.unwrap_or(1).saturating_sub(1);
                    let severity = match f.severity {
                        Severity::Error => 1,
                        Severity::Warning => 2,
                        Severity::Info => 3,
                    };
                    format!(
                        concat!(
                            "      {{\n",
                            "        \"range\": {{ \"start\": {{ \"line\": {}, \"character\": 0 }}, ",
                            "\"end\": {{ \"line\": {}, \"character\": 0 }} }},\n",
                            "        \"severity\": {},\n",
                            "        \"code\": {},\n",
                            "        \"source\": \"plat-verify\",\n",
                            "        \"message\": {}\n",
                            "      }}"
                        ),
                        line,
                        line,
                        severity,
                        json_str(&f.code),
                        json_str(&format!("[{}] {}", f.declaration, f.message)),
                    )
                })
                .collect();
            format!(
                concat!(
                    "    {{\n",
                    "      \"uri\": {},\n",
                    "      \"diagnostics\": [\n",
                    "{}\n",
                    "      ]\n",
                    "    }}"
                ),
                json_str(uri),
                diags.join(",\n"),
            )
        })
        .collect();

    format!("[\n{}\n]\n", entries.join(",\n"))
}

fn file_uri(path: &str) -> String {
    if path.starts_with("file://") {
        return path.to_string();
    }
    let abs = std::path::Path::new(path);
    if abs.is_absolute() {
        format!("file://{}", path)
    } else {
        // Best-effort: canonicalize relative paths
        match abs.canonicalize() {
            Ok(p) => format!("file://{}", p.display()),
            Err(_) => format!("file://{}", path),
        }
    }
}

fn json_str(s: &str) -> String {
    format!(
        "\"{}\"",
        s.replace('\\', "\\\\")
            .replace('"', "\\\"")
            .replace('\n', "\\n")
    )
}

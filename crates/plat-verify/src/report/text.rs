use crate::check::{Finding, Summary};
use crate::config::Severity;

pub fn render(findings: &[Finding], summary: &Summary, name: &str, language: &str) -> String {
    let mut out = String::new();
    out.push_str(&format!("plat-verify: {name} ({language})\n"));

    if findings.is_empty() {
        out.push_str("\nAll checks passed.\n");
    } else {
        out.push('\n');
        for f in findings {
            let sev = match f.severity {
                Severity::Error => "ERROR",
                Severity::Warning => "WARN ",
                Severity::Info => "INFO ",
            };
            out.push_str(&format!("[{}] {sev} {} {}\n", f.code, f.declaration, f.message));
            if let Some(ref expected) = f.expected {
                out.push_str(&format!("       expected: {expected}\n"));
            }
            if let Some(ref src) = f.source_file {
                let line = f.source_line.map(|l| format!(":{l}")).unwrap_or_default();
                out.push_str(&format!("       source: {src}{line}\n"));
            }
            out.push('\n');
        }
    }

    out.push_str(&format!("── Summary {}\n", "─".repeat(40)));
    out.push_str(&format!(
        "  {} error(s), {} warning(s), {} info\n",
        summary.errors, summary.warnings, summary.info
    ));
    out.push_str(&format!(
        "  declarations: {} checked, {} ok, {} issues\n",
        summary.decls_checked,
        summary.decls_ok,
        summary.decls_checked - summary.decls_ok
    ));

    out
}

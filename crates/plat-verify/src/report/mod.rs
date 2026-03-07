pub mod text;
pub mod json;
pub mod lsp;

use crate::check::{Finding, Summary};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Format {
    Text,
    Json,
    Lsp,
}

pub fn render(
    findings: &[Finding],
    summary: &Summary,
    name: &str,
    language: &str,
    format: Format,
) -> String {
    match format {
        Format::Text => text::render(findings, summary, name, language),
        Format::Json => json::render(findings, summary, name, language),
        Format::Lsp => lsp::render(findings),
    }
}

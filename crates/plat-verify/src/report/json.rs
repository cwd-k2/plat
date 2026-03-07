use crate::check::{Finding, Summary};

pub fn render(findings: &[Finding], summary: &Summary, name: &str, language: &str) -> String {
    let findings_json: Vec<String> = findings
        .iter()
        .map(|f| {
            let source = match (&f.source_file, f.source_line) {
                (Some(file), Some(line)) => {
                    format!("{{ \"file\": {}, \"line\": {line} }}", json_str(file))
                }
                (Some(file), None) => {
                    format!("{{ \"file\": {} }}", json_str(file))
                }
                _ => "null".to_string(),
            };
            let expected = f
                .expected
                .as_ref()
                .map(|e| json_str(e))
                .unwrap_or_else(|| "null".to_string());
            format!(
                concat!(
                    "    {{\n",
                    "      \"code\": {},\n",
                    "      \"severity\": {},\n",
                    "      \"declaration\": {},\n",
                    "      \"message\": {},\n",
                    "      \"expected\": {},\n",
                    "      \"source\": {}\n",
                    "    }}"
                ),
                json_str(&f.code),
                json_str(&f.severity.to_string()),
                json_str(&f.declaration),
                json_str(&f.message),
                expected,
                source
            )
        })
        .collect();

    format!(
        concat!(
            "{{\n",
            "  \"name\": {},\n",
            "  \"language\": {},\n",
            "  \"findings\": [\n",
            "{}\n",
            "  ],\n",
            "  \"summary\": {{\n",
            "    \"errors\": {},\n",
            "    \"warnings\": {},\n",
            "    \"info\": {},\n",
            "    \"declarations\": {{ \"checked\": {}, \"ok\": {} }},\n",
            "    \"convergence\": {{ \"types\": [{}, {}], \"fields\": [{}, {}, {}], \"methods\": [{}, {}, {}] }},\n",
            "    \"health_score\": {:.4}\n",
            "  }}\n",
            "}}\n"
        ),
        json_str(name),
        json_str(language),
        findings_json.join(",\n"),
        summary.errors,
        summary.warnings,
        summary.info,
        summary.decls_checked,
        summary.decls_ok,
        summary.convergence.types_found, summary.convergence.types_expected,
        summary.convergence.fields_found, summary.convergence.fields_partial, summary.convergence.fields_expected,
        summary.convergence.methods_found, summary.convergence.methods_partial, summary.convergence.methods_expected,
        summary.convergence.health_score()
    )
}

fn json_str(s: &str) -> String {
    format!(
        "\"{}\"",
        s.replace('\\', "\\\\")
            .replace('"', "\\\"")
            .replace('\n', "\\n")
    )
}

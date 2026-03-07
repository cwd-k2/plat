use plat_manifest::{DeclKind, Manifest};

/// Render a Manifest as a Markdown document.
pub fn render_markdown(manifest: &Manifest) -> String {
    let mut lines = vec![
        format!("# {}", manifest.name),
        String::new(),
    ];

    // Layers
    if !manifest.layers.is_empty() {
        lines.push("## Layers".to_string());
        lines.push(String::new());
        lines.push("| Layer | Dependencies |".to_string());
        lines.push("|-------|-------------|".to_string());
        for l in &manifest.layers {
            let deps = if l.depends.is_empty() {
                "—".to_string()
            } else {
                l.depends.join(", ")
            };
            lines.push(format!("| {} | {} |", l.name, deps));
        }
        lines.push(String::new());
    }

    // Declarations
    for d in &manifest.declarations {
        lines.push(format!("## {}", d.name));
        lines.push(String::new());

        let kind_str = match d.kind {
            DeclKind::Model => "Model",
            DeclKind::Boundary => "Boundary",
            DeclKind::Operation => "Operation",
            DeclKind::Adapter => "Adapter",
            DeclKind::Compose => "Compose",
            DeclKind::Unknown => "Unknown",
        };
        let layer_note = d.layer.as_ref()
            .map(|l| format!(" (`{l}`)"))
            .unwrap_or_default();
        lines.push(format!("**Kind**: {kind_str}{layer_note}"));
        lines.push(String::new());

        // Paths
        if !d.paths.is_empty() {
            let paths: Vec<String> = d.paths.iter().map(|p| format!("`{p}`")).collect();
            lines.push(format!("**Path**: {}", paths.join(", ")));
            lines.push(String::new());
        }

        // Fields (Model)
        if !d.fields.is_empty() {
            lines.push("| Field | Type |".to_string());
            lines.push("|-------|------|".to_string());
            for f in &d.fields {
                lines.push(format!("| {} | `{}` |", f.name, f.typ));
            }
            lines.push(String::new());
        }

        // Ops (Boundary)
        if !d.ops.is_empty() {
            lines.push("| Operation | Input | Output |".to_string());
            lines.push("|-----------|-------|--------|".to_string());
            for op in &d.ops {
                let inputs = render_params(&op.inputs);
                let outputs = render_params(&op.outputs);
                lines.push(format!("| {} | {} | {} |", op.name, inputs, outputs));
            }
            lines.push(String::new());
        }

        // Inputs/Outputs (Operation)
        if !d.inputs.is_empty() || !d.outputs.is_empty() {
            lines.push("| Direction | Name | Type |".to_string());
            lines.push("|-----------|------|------|".to_string());
            for f in &d.inputs {
                lines.push(format!("| in | {} | `{}` |", f.name, f.typ));
            }
            for f in &d.outputs {
                lines.push(format!("| out | {} | `{}` |", f.name, f.typ));
            }
            lines.push(String::new());
        }

        // Needs
        if !d.needs.is_empty() {
            lines.push(format!("**Depends on**: {}", d.needs.join(", ")));
            lines.push(String::new());
        }

        // Implements
        if let Some(ref b) = d.implements {
            lines.push(format!("**Implements**: {b}"));
            lines.push(String::new());
        }

        // Injects
        if !d.injects.is_empty() {
            lines.push("| Injection | Type |".to_string());
            lines.push("|-----------|------|".to_string());
            for f in &d.injects {
                lines.push(format!("| {} | `{}` |", f.name, f.typ));
            }
            lines.push(String::new());
        }
    }

    // Bindings
    if !manifest.bindings.is_empty() {
        lines.push("## Bindings".to_string());
        lines.push(String::new());
        lines.push("| Boundary | Adapter |".to_string());
        lines.push("|----------|---------|".to_string());
        for b in &manifest.bindings {
            lines.push(format!("| {} | {} |", b.boundary, b.adapter));
        }
        lines.push(String::new());
    }

    lines.join("\n")
}

fn render_params(fields: &[plat_manifest::Field]) -> String {
    if fields.is_empty() {
        "—".to_string()
    } else {
        fields.iter()
            .map(|f| format!("`{}`", f.typ))
            .collect::<Vec<_>>()
            .join(", ")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_manifest() -> Manifest {
        let json = r#"{
            "name": "order-service",
            "layers": [
                {"name": "domain", "depends": []},
                {"name": "app", "depends": ["domain"]}
            ],
            "declarations": [
                {
                    "name": "Order",
                    "kind": "model",
                    "layer": "domain",
                    "fields": [{"name": "id", "type": "UUID"}, {"name": "total", "type": "Decimal"}]
                },
                {
                    "name": "OrderRepo",
                    "kind": "boundary",
                    "layer": "domain",
                    "ops": [{"name": "Save", "inputs": [{"name": "order", "type": "Order"}], "outputs": [{"name": "err", "type": "Error"}]}]
                },
                {
                    "name": "PlaceOrder",
                    "kind": "operation",
                    "layer": "app",
                    "needs": ["OrderRepo"]
                },
                {
                    "name": "PgOrderRepo",
                    "kind": "adapter",
                    "layer": "app",
                    "implements": "OrderRepo",
                    "injects": [{"name": "db", "type": "Database"}]
                }
            ],
            "bindings": [{"boundary": "OrderRepo", "adapter": "PgOrderRepo"}]
        }"#;
        serde_json::from_str(json).unwrap()
    }

    #[test]
    fn markdown_has_title() {
        let md = render_markdown(&sample_manifest());
        assert!(md.starts_with("# order-service"));
    }

    #[test]
    fn markdown_has_layers() {
        let md = render_markdown(&sample_manifest());
        assert!(md.contains("## Layers"));
        assert!(md.contains("| domain | — |"));
        assert!(md.contains("| app | domain |"));
    }

    #[test]
    fn markdown_has_fields() {
        let md = render_markdown(&sample_manifest());
        assert!(md.contains("| id | `UUID` |"));
        assert!(md.contains("| total | `Decimal` |"));
    }

    #[test]
    fn markdown_has_ops() {
        let md = render_markdown(&sample_manifest());
        assert!(md.contains("| Save |"));
    }

    #[test]
    fn markdown_has_needs() {
        let md = render_markdown(&sample_manifest());
        assert!(md.contains("**Depends on**: OrderRepo"));
    }

    #[test]
    fn markdown_has_implements() {
        let md = render_markdown(&sample_manifest());
        assert!(md.contains("**Implements**: OrderRepo"));
    }

    #[test]
    fn markdown_has_bindings() {
        let md = render_markdown(&sample_manifest());
        assert!(md.contains("## Bindings"));
        assert!(md.contains("| OrderRepo | PgOrderRepo |"));
    }
}

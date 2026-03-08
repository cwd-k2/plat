use plat_manifest::{DeclKind, Manifest};

/// Mermaid graph direction.
#[derive(Clone, Copy, Default, clap::ValueEnum)]
pub enum Direction {
    /// Left to right
    #[default]
    LR,
    /// Top down
    TD,
    /// Right to left
    RL,
    /// Bottom to top
    BT,
}

impl std::fmt::Display for Direction {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Direction::LR => write!(f, "LR"),
            Direction::TD => write!(f, "TD"),
            Direction::RL => write!(f, "RL"),
            Direction::BT => write!(f, "BT"),
        }
    }
}

/// Render a Manifest as a Mermaid flowchart.
pub fn render_mermaid(manifest: &Manifest, direction: Direction) -> String {
    let mut lines = vec![format!("graph {direction}")];

    // Nodes
    for d in &manifest.declarations {
        let id = sanitize(&d.name);
        let shape = match d.kind {
            DeclKind::Model => format!("  {id}[{}]", d.name),
            DeclKind::Boundary => format!("  {id}([{}])", d.name),
            DeclKind::Operation => format!("  {id}[[{}]]", d.name),
            DeclKind::Adapter => format!("  {id}[/{}\\]", d.name),
            DeclKind::Compose => format!("  {id}{{{{{}}}}}", d.name),
            DeclKind::Unknown => format!("  {id}[{}]", d.name),
        };
        lines.push(shape);
    }

    let decl_names: std::collections::HashSet<&str> =
        manifest.declarations.iter().map(|d| d.name.as_str()).collect();

    // Edges
    for d in &manifest.declarations {
        let me = sanitize(&d.name);
        match d.kind {
            DeclKind::Operation => {
                for target in &d.needs {
                    lines.push(format!("  {me} -.->|needs| {}", sanitize(target)));
                }
            }
            DeclKind::Adapter => {
                if let Some(ref target) = d.implements {
                    lines.push(format!("  {me} -->|implements| {}", sanitize(target)));
                }
                for inj in &d.injects {
                    if decl_names.contains(inj.name.as_str()) {
                        lines.push(format!("  {me} -.->|inject| {}", sanitize(&inj.name)));
                    }
                }
            }
            _ => {}
        }
    }

    // Bindings
    for b in &manifest.bindings {
        lines.push(format!(
            "  {} ===>|bind| {}",
            sanitize(&b.boundary),
            sanitize(&b.adapter)
        ));
    }

    lines.push(String::new());
    lines.join("\n")
}

fn sanitize(name: &str) -> String {
    name.chars()
        .filter(|c| c.is_alphanumeric() || *c == '_')
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_manifest() -> Manifest {
        let json = r#"{
            "name": "test-arch",
            "layers": [
                {"name": "domain", "depends": []},
                {"name": "app", "depends": ["domain"]}
            ],
            "declarations": [
                {"name": "Order", "kind": "model", "layer": "domain", "fields": [{"name": "id", "type": "UUID"}]},
                {"name": "OrderRepo", "kind": "boundary", "layer": "domain", "ops": [{"name": "Save", "inputs": [{"name": "order", "type": "Order"}], "outputs": []}]},
                {"name": "PlaceOrder", "kind": "operation", "layer": "app", "needs": ["OrderRepo"]},
                {"name": "PgOrderRepo", "kind": "adapter", "layer": "app", "implements": "OrderRepo"}
            ],
            "bindings": [{"boundary": "OrderRepo", "adapter": "PgOrderRepo"}]
        }"#;
        serde_json::from_str(json).unwrap()
    }

    #[test]
    fn mermaid_contains_all_nodes() {
        let mmd = render_mermaid(&sample_manifest(), Direction::default());
        assert!(mmd.contains("Order[Order]"));
        assert!(mmd.contains("OrderRepo([OrderRepo])"));
        assert!(mmd.contains("PlaceOrder[[PlaceOrder]]"));
        assert!(mmd.contains("PgOrderRepo[/PgOrderRepo\\]"));
    }

    #[test]
    fn mermaid_contains_edges() {
        let mmd = render_mermaid(&sample_manifest(), Direction::default());
        assert!(mmd.contains("PlaceOrder -.->|needs| OrderRepo"));
        assert!(mmd.contains("PgOrderRepo -->|implements| OrderRepo"));
        assert!(mmd.contains("OrderRepo ===>|bind| PgOrderRepo"));
    }

    #[test]
    fn mermaid_starts_with_graph_lr() {
        let mmd = render_mermaid(&sample_manifest(), Direction::default());
        assert!(mmd.starts_with("graph LR"));
    }
}

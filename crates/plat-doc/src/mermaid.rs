use plat_manifest::{DeclKind, Declaration, Manifest};
use std::collections::HashSet;

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

    let decl_names: HashSet<&str> =
        manifest.declarations.iter().map(|d| d.name.as_str()).collect();

    // Compose groups (first-claim-wins)
    let mut claimed: HashSet<&str> = HashSet::new();
    let mut groups: Vec<(&str, Vec<&Declaration>)> = Vec::new();

    for d in &manifest.declarations {
        if d.kind != DeclKind::Compose || d.entries.is_empty() {
            continue;
        }
        let members: Vec<&Declaration> = d
            .entries
            .iter()
            .filter(|e| !claimed.contains(e.as_str()))
            .filter_map(|e| manifest.declarations.iter().find(|decl| decl.name == **e))
            .collect();
        for m in &members {
            claimed.insert(&m.name);
        }
        if !members.is_empty() {
            groups.push((&d.name, members));
        }
    }

    // Subgraphs
    for (name, members) in &groups {
        lines.push(format!("  subgraph {}", sanitize(name)));
        for d in members {
            lines.push(format!("    {}", node_shape(d)));
        }
        lines.push("  end".to_string());
    }

    // Ungrouped nodes
    for d in &manifest.declarations {
        if claimed.contains(d.name.as_str()) {
            continue;
        }
        if d.kind == DeclKind::Compose && !d.entries.is_empty() {
            continue;
        }
        lines.push(format!("  {}", node_shape(d)));
    }

    // Structural edges
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

    // Type reference edges
    for d in &manifest.declarations {
        if d.kind == DeclKind::Compose {
            continue;
        }
        let me = sanitize(&d.name);
        for r in type_refs(d) {
            if decl_names.contains(r.as_str()) && r != d.name {
                lines.push(format!("  {me} -.-> {}", sanitize(&r)));
            }
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

fn node_shape(d: &Declaration) -> String {
    let id = sanitize(&d.name);
    match d.kind {
        DeclKind::Model => format!("{id}[{}]", d.name),
        DeclKind::Boundary => format!("{id}([{}])", d.name),
        DeclKind::Operation => format!("{id}[[{}]]", d.name),
        DeclKind::Adapter => format!("{id}[/{}\\]", d.name),
        DeclKind::Compose => format!("{id}{{{{{}}}}}", d.name),
        DeclKind::Unknown => format!("{id}[{}]", d.name),
    }
}

fn type_refs(d: &Declaration) -> HashSet<String> {
    let mut refs = HashSet::new();
    for f in d.fields.iter().chain(d.inputs.iter()).chain(d.outputs.iter()).chain(d.injects.iter()) {
        extract_type_refs(&f.typ, &mut refs);
    }
    for op in &d.ops {
        for f in op.inputs.iter().chain(op.outputs.iter()) {
            extract_type_refs(&f.typ, &mut refs);
        }
    }
    refs
}

fn extract_type_refs(typ: &str, refs: &mut HashSet<String>) {
    if let Some(start) = typ.find('<') {
        if let Some(end) = typ.rfind('>') {
            for part in typ[start + 1..end].split(',') {
                extract_type_refs(part.trim(), refs);
            }
        }
    } else {
        refs.insert(typ.to_string());
    }
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

    #[test]
    fn mermaid_type_ref_edges() {
        let mmd = render_mermaid(&sample_manifest(), Direction::default());
        // OrderRepo.ops.Save has input type Order → edge to Order
        assert!(mmd.contains("OrderRepo -.-> Order"));
    }

    fn grouped_manifest() -> Manifest {
        let json = r#"{
            "name": "test-grouped",
            "layers": [
                {"name": "domain", "depends": []},
                {"name": "app", "depends": ["domain"]}
            ],
            "declarations": [
                {"name": "Money", "kind": "model", "layer": "domain", "fields": []},
                {"name": "Order", "kind": "model", "layer": "domain", "fields": [{"name": "total", "type": "Money"}]},
                {"name": "PlaceOrder", "kind": "operation", "layer": "app", "needs": []},
                {"name": "SharedKernel", "kind": "compose", "entries": ["Money"]},
                {"name": "OrderFeature", "kind": "compose", "entries": ["Order", "PlaceOrder"]}
            ],
            "bindings": []
        }"#;
        serde_json::from_str(json).unwrap()
    }

    #[test]
    fn mermaid_subgraphs() {
        let mmd = render_mermaid(&grouped_manifest(), Direction::default());
        assert!(mmd.contains("subgraph SharedKernel"));
        assert!(mmd.contains("subgraph OrderFeature"));
        assert!(mmd.contains("end"));
    }

    #[test]
    fn mermaid_first_claim_wins() {
        let json = r#"{
            "name": "test-overlap",
            "layers": [],
            "declarations": [
                {"name": "A", "kind": "model", "fields": []},
                {"name": "G1", "kind": "compose", "entries": ["A"]},
                {"name": "G2", "kind": "compose", "entries": ["A"]}
            ],
            "bindings": []
        }"#;
        let m: Manifest = serde_json::from_str(json).unwrap();
        let mmd = render_mermaid(&m, Direction::default());
        assert!(mmd.contains("subgraph G1"));
        // G2 has no unclaimed members → no subgraph
        assert!(!mmd.contains("subgraph G2"));
    }
}

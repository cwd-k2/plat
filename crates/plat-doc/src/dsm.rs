use plat_manifest::Manifest;
use std::collections::{HashMap, HashSet};

/// Render a Dependency Structure Matrix (DSM) as a text table.
///
/// Declarations are grouped by layer (in manifest order), then alphabetically
/// within each layer. Compose declarations (no layer) are appended at the end.
///
/// Cell marks:
/// - `.` — diagonal (self)
/// - `x` — row depends on column (downward, expected)
/// - `^` — row depends on column (upward, potential violation)
pub fn render_dsm(manifest: &Manifest) -> String {
    let layer_order: HashMap<&str, usize> = manifest
        .layers
        .iter()
        .enumerate()
        .map(|(i, l)| (l.name.as_str(), i))
        .collect();

    // Sorted declarations: by layer order, then alphabetically
    let mut sorted: Vec<&str> = manifest
        .declarations
        .iter()
        .map(|d| d.name.as_str())
        .collect();

    let decl_layer: HashMap<&str, Option<&str>> = manifest
        .declarations
        .iter()
        .map(|d| (d.name.as_str(), d.layer.as_deref()))
        .collect();

    sorted.sort_by(|a, b| {
        let la = decl_layer.get(a).and_then(|l| *l);
        let lb = decl_layer.get(b).and_then(|l| *l);
        let oa = la.and_then(|l| layer_order.get(l)).copied().unwrap_or(usize::MAX);
        let ob = lb.and_then(|l| layer_order.get(l)).copied().unwrap_or(usize::MAX);
        oa.cmp(&ob).then_with(|| a.cmp(b))
    });

    let name_to_idx: HashMap<&str, usize> = sorted
        .iter()
        .enumerate()
        .map(|(i, n)| (*n, i))
        .collect();

    let n = sorted.len();

    // Build dependency set: (row, col) means row depends on col
    let mut deps: HashSet<(usize, usize)> = HashSet::new();

    for d in &manifest.declarations {
        let Some(&row) = name_to_idx.get(d.name.as_str()) else {
            continue;
        };
        // needs
        for target in &d.needs {
            if let Some(&col) = name_to_idx.get(target.as_str()) {
                deps.insert((row, col));
            }
        }
        // implements
        if let Some(ref target) = d.implements {
            if let Some(&col) = name_to_idx.get(target.as_str()) {
                deps.insert((row, col));
            }
        }
        // field / input / output type references
        let all_fields = d.fields.iter()
            .chain(d.inputs.iter())
            .chain(d.outputs.iter());
        for f in all_fields {
            if let Some(&col) = name_to_idx.get(f.typ.as_str()) {
                if col != row {
                    deps.insert((row, col));
                }
            }
        }
    }

    // Column width: max of name length and 3 (for marks)
    let col_w: Vec<usize> = sorted.iter().map(|n| n.len().max(3)).collect();
    let label_w = sorted.iter().map(|n| n.len()).max().unwrap_or(0);

    let mut out = String::new();

    // Header
    out.push_str(&" ".repeat(label_w + 3));
    for (j, name) in sorted.iter().enumerate() {
        out.push_str(&format!("{:^w$} ", name, w = col_w[j]));
    }
    out.push('\n');

    // Separator
    out.push_str(&" ".repeat(label_w + 3));
    for j in 0..n {
        out.push_str(&"-".repeat(col_w[j]));
        out.push(' ');
    }
    out.push('\n');

    // Rows
    for (i, name) in sorted.iter().enumerate() {
        out.push_str(&format!("{:>w$} | ", name, w = label_w));
        for j in 0..n {
            let mark = if i == j {
                "."
            } else if deps.contains(&(i, j)) {
                if i > j { "x" } else { "^" }
            } else {
                ""
            };
            out.push_str(&format!("{:^w$} ", mark, w = col_w[j]));
        }
        out.push('\n');
    }

    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_manifest() -> Manifest {
        let json = r#"{
            "name": "test-arch",
            "layers": [
                {"name": "domain", "depends": []},
                {"name": "app", "depends": ["domain"]},
                {"name": "infra", "depends": ["domain", "app"]}
            ],
            "declarations": [
                {"name": "Order", "kind": "model", "layer": "domain",
                 "fields": [{"name": "id", "type": "UUID"}]},
                {"name": "OrderRepo", "kind": "boundary", "layer": "domain",
                 "ops": [{"name": "Save", "inputs": [{"name": "order", "type": "Order"}], "outputs": []}]},
                {"name": "PlaceOrder", "kind": "operation", "layer": "app",
                 "needs": ["OrderRepo"],
                 "inputs": [{"name": "item", "type": "Order"}]},
                {"name": "PgOrderRepo", "kind": "adapter", "layer": "infra",
                 "implements": "OrderRepo"}
            ],
            "bindings": [{"boundary": "OrderRepo", "adapter": "PgOrderRepo"}]
        }"#;
        serde_json::from_str(json).unwrap()
    }

    #[test]
    fn dsm_has_all_names() {
        let dsm = render_dsm(&sample_manifest());
        assert!(dsm.contains("Order"));
        assert!(dsm.contains("OrderRepo"));
        assert!(dsm.contains("PlaceOrder"));
        assert!(dsm.contains("PgOrderRepo"));
    }

    #[test]
    fn dsm_diagonal_is_dot() {
        let dsm = render_dsm(&sample_manifest());
        // Each row should have exactly one '.'
        for line in dsm.lines().skip(2) {
            let dots: Vec<_> = line.match_indices('.').collect();
            assert_eq!(dots.len(), 1, "Expected exactly one dot in: {line}");
        }
    }

    #[test]
    fn dsm_needs_marked() {
        let dsm = render_dsm(&sample_manifest());
        // PlaceOrder (app) depends on OrderRepo (domain) → downward → 'x'
        // PlaceOrder is row 2, OrderRepo is col 1 (sorted: Order, OrderRepo, PlaceOrder, PgOrderRepo)
        assert!(dsm.contains("x"), "Expected 'x' for needs dependency");
    }

    #[test]
    fn dsm_implements_marked() {
        let dsm = render_dsm(&sample_manifest());
        // PgOrderRepo (infra, row 3) implements OrderRepo (domain, col 1) → downward → 'x'
        // Count total 'x' marks: PlaceOrder→OrderRepo, PlaceOrder→Order, PgOrderRepo→OrderRepo = 3
        let x_count = dsm.matches('x').count();
        assert!(x_count >= 3, "Expected at least 3 'x' marks, got {x_count}");
    }

    #[test]
    fn dsm_field_ref_marked() {
        let dsm = render_dsm(&sample_manifest());
        // PlaceOrder has input field of type Order → PlaceOrder depends on Order
        // This is a downward dependency (app → domain) so marked 'x'
        // No upward ('^') dependencies in this well-formed architecture
        assert!(!dsm.contains("^"), "Expected no upward dependencies in well-formed arch");
    }

    #[test]
    fn dsm_sorted_by_layer() {
        let dsm = render_dsm(&sample_manifest());
        let rows: Vec<&str> = dsm
            .lines()
            .skip(2) // header + separator
            .filter_map(|l| l.split('|').next())
            .map(|s| s.trim())
            .collect();
        // domain declarations first, then app, then infra
        let order_pos = rows.iter().position(|&n| n == "Order").unwrap();
        let place_pos = rows.iter().position(|&n| n == "PlaceOrder").unwrap();
        let pg_pos = rows.iter().position(|&n| n == "PgOrderRepo").unwrap();
        assert!(order_pos < place_pos, "domain before app");
        assert!(place_pos < pg_pos, "app before infra");
    }
}

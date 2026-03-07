use std::collections::BTreeMap;
use std::io::{self, BufRead, Write};

use plat_manifest::{DeclKind, Manifest};

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let manifest = if args.len() > 1 {
        match load_manifest(&args[1]) {
            Ok(m) => {
                eprintln!("loaded {} ({} declarations)", m.name, m.declarations.len());
                Some(m)
            }
            Err(e) => {
                eprintln!("error: {e}");
                None
            }
        }
    } else {
        None
    };

    let mut state = ReplState { manifest };

    let stdin = io::stdin();
    let mut stdout = io::stdout();

    loop {
        let prompt = match &state.manifest {
            Some(m) => format!("plat({})> ", m.name),
            None => "plat> ".to_string(),
        };
        print!("{prompt}");
        let _ = stdout.flush();

        let mut line = String::new();
        if stdin.lock().read_line(&mut line).unwrap_or(0) == 0 {
            break;
        }
        let line = line.trim();
        if line.is_empty() {
            continue;
        }

        let parts: Vec<&str> = line.splitn(2, ' ').collect();
        let cmd = parts[0];
        let arg = parts.get(1).copied().unwrap_or("");

        match cmd {
            "load" => cmd_load(&mut state, arg),
            "info" => cmd_info(&state),
            "decls" => cmd_decls(&state, arg),
            "show" => cmd_show(&state, arg),
            "layers" => cmd_layers(&state),
            "deps" => cmd_deps(&state, arg),
            "types" => cmd_types(&state),
            "bindings" => cmd_bindings(&state),
            "relations" => cmd_relations(&state, arg),
            "find" => cmd_find(&state, arg),
            "stats" => cmd_stats(&state),
            "help" | "?" => cmd_help(),
            "quit" | "exit" => break,
            _ => eprintln!("unknown command: {cmd} (type 'help' for commands)"),
        }
    }
}

struct ReplState {
    manifest: Option<Manifest>,
}

impl ReplState {
    fn require_manifest(&self) -> Option<&Manifest> {
        match &self.manifest {
            Some(m) => Some(m),
            None => {
                eprintln!("no manifest loaded (use 'load <path>')");
                None
            }
        }
    }
}

fn load_manifest(path: &str) -> Result<Manifest, String> {
    let text = std::fs::read_to_string(path).map_err(|e| format!("cannot read {path}: {e}"))?;
    serde_json::from_str(&text).map_err(|e| format!("invalid JSON: {e}"))
}

fn cmd_load(state: &mut ReplState, arg: &str) {
    if arg.is_empty() {
        eprintln!("usage: load <manifest.json>");
        return;
    }
    match load_manifest(arg) {
        Ok(m) => {
            println!("loaded {} ({} declarations)", m.name, m.declarations.len());
            state.manifest = Some(m);
        }
        Err(e) => eprintln!("error: {e}"),
    }
}

fn cmd_info(state: &ReplState) {
    let Some(m) = state.require_manifest() else { return };
    println!("name:         {}", m.name);
    println!("schema:       {}", m.schema_version);
    println!("layers:       {}", m.layers.len());
    println!("declarations: {}", m.declarations.len());
    println!("bindings:     {}", m.bindings.len());
    println!("relations:    {}", m.relations.len());
    println!("constraints:  {}", m.constraints.len());
    if !m.type_aliases.is_empty() {
        println!("type aliases: {}", m.type_aliases.len());
    }
    if !m.custom_types.is_empty() {
        println!("custom types: {}", m.custom_types.join(", "));
    }
}

fn cmd_decls(state: &ReplState, filter: &str) {
    let Some(m) = state.require_manifest() else { return };
    let kind_filter = match filter {
        "models" | "model" => Some(DeclKind::Model),
        "boundaries" | "boundary" => Some(DeclKind::Boundary),
        "operations" | "operation" => Some(DeclKind::Operation),
        "adapters" | "adapter" => Some(DeclKind::Adapter),
        "composes" | "compose" => Some(DeclKind::Compose),
        "" => None,
        other => {
            eprintln!("unknown filter: {other} (model|boundary|operation|adapter|compose)");
            return;
        }
    };

    for d in &m.declarations {
        if let Some(k) = kind_filter {
            if d.kind != k {
                continue;
            }
        }
        let layer = d.layer.as_deref().unwrap_or("-");
        println!("  {:12} {:30} [{}]", d.kind.to_string(), d.name, layer);
    }
}

fn cmd_show(state: &ReplState, name: &str) {
    let Some(m) = state.require_manifest() else { return };
    if name.is_empty() {
        eprintln!("usage: show <declaration-name>");
        return;
    }
    let Some(d) = m.declarations.iter().find(|d| d.name == name) else {
        eprintln!("declaration not found: {name}");
        return;
    };

    println!("{} {} ({})", d.kind, d.name, d.layer.as_deref().unwrap_or("no layer"));

    if !d.fields.is_empty() {
        println!("  fields:");
        for f in &d.fields {
            println!("    {}: {}", f.name, f.typ);
        }
    }

    if !d.ops.is_empty() {
        println!("  ops:");
        for op in &d.ops {
            let ins: Vec<String> = op.inputs.iter().map(|f| format!("{}: {}", f.name, f.typ)).collect();
            let outs: Vec<String> = op.outputs.iter().map(|f| format!("{}: {}", f.name, f.typ)).collect();
            println!("    {}({}) -> ({})", op.name, ins.join(", "), outs.join(", "));
        }
    }

    if !d.inputs.is_empty() {
        println!("  inputs:");
        for f in &d.inputs {
            println!("    {}: {}", f.name, f.typ);
        }
    }

    if !d.outputs.is_empty() {
        println!("  outputs:");
        for f in &d.outputs {
            println!("    {}: {}", f.name, f.typ);
        }
    }

    if !d.needs.is_empty() {
        println!("  needs: {}", d.needs.join(", "));
    }

    if let Some(impl_name) = &d.implements {
        println!("  implements: {impl_name}");
    }

    if !d.injects.is_empty() {
        println!("  injects:");
        for f in &d.injects {
            println!("    {}: {}", f.name, f.typ);
        }
    }

    if !d.entries.is_empty() {
        println!("  entries: {}", d.entries.join(", "));
    }

    if !d.paths.is_empty() {
        println!("  paths: {}", d.paths.join(", "));
    }

    if !d.meta.is_empty() {
        println!("  meta:");
        let mut keys: Vec<_> = d.meta.keys().collect();
        keys.sort();
        for k in keys {
            println!("    {}: {}", k, d.meta[k]);
        }
    }
}

fn cmd_layers(state: &ReplState) {
    let Some(m) = state.require_manifest() else { return };
    for l in &m.layers {
        let deps = if l.depends.is_empty() {
            "(none)".to_string()
        } else {
            l.depends.join(", ")
        };
        println!("  {} → depends on: {}", l.name, deps);
    }
}

fn cmd_deps(state: &ReplState, name: &str) {
    let Some(m) = state.require_manifest() else { return };
    if name.is_empty() {
        eprintln!("usage: deps <declaration-name>");
        return;
    }
    let Some(d) = m.declarations.iter().find(|d| d.name == name) else {
        eprintln!("declaration not found: {name}");
        return;
    };

    // Direct needs
    if !d.needs.is_empty() {
        println!("  needs: {}", d.needs.join(", "));
    }

    // Who needs this declaration
    let needed_by: Vec<&str> = m
        .declarations
        .iter()
        .filter(|dd| dd.needs.contains(&name.to_string()))
        .map(|dd| dd.name.as_str())
        .collect();
    if !needed_by.is_empty() {
        println!("  needed by: {}", needed_by.join(", "));
    }

    // Implements
    if let Some(impl_name) = &d.implements {
        println!("  implements: {impl_name}");
    }

    // Implemented by
    let implemented_by: Vec<&str> = m
        .declarations
        .iter()
        .filter(|dd| dd.implements.as_deref() == Some(name))
        .map(|dd| dd.name.as_str())
        .collect();
    if !implemented_by.is_empty() {
        println!("  implemented by: {}", implemented_by.join(", "));
    }

    // Bound to
    for b in &m.bindings {
        if b.boundary == name {
            println!("  bound to adapter: {}", b.adapter);
        }
        if b.adapter == name {
            println!("  bound to boundary: {}", b.boundary);
        }
    }
}

fn cmd_types(state: &ReplState) {
    let Some(m) = state.require_manifest() else { return };
    if !m.type_aliases.is_empty() {
        println!("  type aliases:");
        for ta in &m.type_aliases {
            println!("    {} = {}", ta.name, ta.typ);
        }
    }
    if !m.custom_types.is_empty() {
        println!("  custom types: {}", m.custom_types.join(", "));
    }
    if m.type_aliases.is_empty() && m.custom_types.is_empty() {
        println!("  (no type aliases or custom types)");
    }
}

fn cmd_bindings(state: &ReplState) {
    let Some(m) = state.require_manifest() else { return };
    if m.bindings.is_empty() {
        println!("  (no bindings)");
    }
    for b in &m.bindings {
        println!("  {} ← {}", b.boundary, b.adapter);
    }
}

fn cmd_relations(state: &ReplState, filter: &str) {
    let Some(m) = state.require_manifest() else { return };
    if m.relations.is_empty() {
        println!("  (no explicit relations)");
        return;
    }
    for r in &m.relations {
        if !filter.is_empty() && r.source != filter && r.target != filter && r.kind != filter {
            continue;
        }
        println!("  {} --[{}]--> {}", r.source, r.kind, r.target);
    }
}

fn cmd_find(state: &ReplState, pattern: &str) {
    let Some(m) = state.require_manifest() else { return };
    if pattern.is_empty() {
        eprintln!("usage: find <pattern>");
        return;
    }
    let lower = pattern.to_lowercase();
    for d in &m.declarations {
        if d.name.to_lowercase().contains(&lower) {
            let layer = d.layer.as_deref().unwrap_or("-");
            println!("  {:12} {:30} [{}]", d.kind.to_string(), d.name, layer);
        }
    }
}

fn cmd_stats(state: &ReplState) {
    let Some(m) = state.require_manifest() else { return };

    let mut by_kind: BTreeMap<String, usize> = BTreeMap::new();
    let mut by_layer: BTreeMap<String, usize> = BTreeMap::new();

    for d in &m.declarations {
        *by_kind.entry(d.kind.to_string()).or_default() += 1;
        let layer = d.layer.as_deref().unwrap_or("(none)").to_string();
        *by_layer.entry(layer).or_default() += 1;
    }

    println!("  by kind:");
    for (k, n) in &by_kind {
        println!("    {:12} {}", k, n);
    }

    println!("  by layer:");
    for (l, n) in &by_layer {
        println!("    {:12} {}", l, n);
    }

    // Count total ops, fields
    let total_ops: usize = m.declarations.iter().map(|d| d.ops.len()).sum();
    let total_fields: usize = m.declarations.iter().map(|d| d.fields.len()).sum();
    println!("  total fields: {}", total_fields);
    println!("  total ops:    {}", total_ops);
}

fn cmd_help() {
    println!("plat-repl commands:");
    println!("  load <path>      Load a manifest JSON file");
    println!("  info             Show manifest summary");
    println!("  decls [kind]     List declarations (model|boundary|operation|adapter|compose)");
    println!("  show <name>      Show declaration details");
    println!("  layers           Show layer definitions");
    println!("  deps <name>      Show dependencies for a declaration");
    println!("  types            Show type aliases and custom types");
    println!("  bindings         Show boundary-adapter bindings");
    println!("  relations [name] Show explicit relations (optionally filtered)");
    println!("  find <pattern>   Search declarations by name");
    println!("  stats            Show architecture statistics");
    println!("  help             Show this help");
    println!("  quit             Exit");
}

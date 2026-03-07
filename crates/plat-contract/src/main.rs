use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process;

use clap::Parser;
use plat_manifest::naming::convert;
use plat_manifest::typemap;
use plat_manifest::{Case, DeclKind, Declaration, Language, Manifest};

/// CLI-level language selector (implements clap::ValueEnum).
#[derive(Clone, Copy, clap::ValueEnum)]
enum Lang {
    Go,
    #[value(name = "typescript")]
    TypeScript,
    Rust,
}

impl Lang {
    fn into_language(self) -> Language {
        match self {
            Self::Go => Language::Go,
            Self::TypeScript => Language::TypeScript,
            Self::Rust => Language::Rust,
        }
    }
}

#[derive(Parser)]
#[command(
    name = "plat-contract",
    version,
    about = "Generate contract test skeletons from plat architecture manifest"
)]
struct Cli {
    /// Manifest JSON file path
    manifest: PathBuf,

    /// Target language: go, typescript, rust
    #[arg(short, long)]
    language: Lang,

    /// Output directory
    #[arg(short, long, default_value = ".")]
    output: PathBuf,

    /// Layer to directory mapping (repeatable, e.g. --layer-dir domain=src/domain)
    #[arg(long = "layer-dir", value_name = "LAYER=DIR")]
    layer_dir: Vec<String>,

    /// Type mapping override (repeatable, e.g. --type-map UUID=string)
    #[arg(long = "type-map", value_name = "TYPE=TYPE")]
    type_map: Vec<String>,
}

fn main() {
    let cli = Cli::parse();

    let manifest_text = match std::fs::read_to_string(&cli.manifest) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("error: cannot read manifest {}: {e}", cli.manifest.display());
            process::exit(2);
        }
    };
    let manifest: Manifest = match serde_json::from_str(&manifest_text) {
        Ok(m) => m,
        Err(e) => {
            eprintln!("error: invalid manifest JSON: {e}");
            process::exit(2);
        }
    };

    let language = cli.language.into_language();
    let layer_dirs = parse_kv_pairs(&cli.layer_dir);
    let user_type_map = parse_kv_pairs(&cli.type_map);

    let files = generate(&manifest, language, &layer_dirs, &user_type_map);

    for (path, content) in &files {
        let full = cli.output.join(path);
        if let Some(parent) = full.parent() {
            if let Err(e) = std::fs::create_dir_all(parent) {
                eprintln!("error: cannot create directory {}: {e}", parent.display());
                process::exit(2);
            }
        }
        if let Err(e) = std::fs::write(&full, content) {
            eprintln!("error: cannot write {}: {e}", full.display());
            process::exit(2);
        }
        println!("  wrote {}", full.display());
    }

    println!("generated {} contract file(s)", files.len());
}

fn parse_kv_pairs(pairs: &[String]) -> HashMap<String, String> {
    let mut map = HashMap::new();
    for pair in pairs {
        if let Some((k, v)) = pair.split_once('=') {
            map.insert(k.to_string(), v.to_string());
        }
    }
    map
}

fn generate(
    manifest: &Manifest,
    lang: Language,
    layer_dirs: &HashMap<String, String>,
    user_type_map: &HashMap<String, String>,
) -> Vec<(PathBuf, String)> {
    let boundaries: Vec<&Declaration> = manifest
        .declarations
        .iter()
        .filter(|d| d.kind == DeclKind::Boundary)
        .collect();

    let adapters: Vec<&Declaration> = manifest
        .declarations
        .iter()
        .filter(|d| d.kind == DeclKind::Adapter)
        .collect();

    let mut files = Vec::new();

    for boundary in &boundaries {
        let known_adapters: Vec<&str> = adapters
            .iter()
            .filter(|a| {
                a.implements
                    .as_ref()
                    .is_some_and(|i| i == &boundary.name)
            })
            .map(|a| a.name.as_str())
            .collect();

        let layer_dir = resolve_layer_dir(boundary, layer_dirs);

        let (path, content) = match lang {
            Language::Go => gen_go(boundary, &known_adapters, &layer_dir, user_type_map),
            Language::TypeScript => gen_typescript(boundary, &known_adapters, &layer_dir),
            Language::Rust => gen_rust(boundary, &known_adapters, &layer_dir, user_type_map),
        };

        files.push((path, content));
    }

    files
}

fn resolve_layer_dir(decl: &Declaration, layer_dirs: &HashMap<String, String>) -> String {
    let layer = decl.layer.as_deref().unwrap_or("default");
    layer_dirs
        .get(layer)
        .cloned()
        .unwrap_or_else(|| layer.to_string())
}

fn to_kebab(name: &str) -> String {
    convert(name, Case::Snake).replace('_', "-")
}

// ---------------------------------------------------------------------------
// Go
// ---------------------------------------------------------------------------

fn gen_go(
    boundary: &Declaration,
    adapters: &[&str],
    layer_dir: &str,
    user_type_map: &HashMap<String, String>,
) -> (PathBuf, String) {
    let snake = convert(&boundary.name, Case::Snake);
    let pascal = convert(&boundary.name, Case::Pascal);
    let pkg = layer_dir.rsplit('/').next().unwrap_or(layer_dir);
    let path = Path::new(layer_dir).join(format!("{snake}_contract_test.go"));

    let adapter_names = adapters.join(", ");

    let mut out = String::new();
    out.push_str(&format!("package {pkg}_test\n"));
    out.push('\n');
    out.push_str("import \"testing\"\n");
    out.push('\n');
    out.push_str(&format!("// Contract tests for {pascal}\n"));
    out.push_str(&format!("// Known adapters: {adapter_names}\n"));
    out.push('\n');
    out.push_str(&format!("type {pascal}Contract struct {{\n"));
    out.push_str(&format!("\tNew func() {pascal}\n"));
    out.push_str("}\n");

    let defaults = typemap::defaults(Language::Go);

    for op in &boundary.ops {
        let op_pascal = convert(&op.name, Case::Pascal);
        out.push('\n');
        out.push_str(&format!(
            "func (c {pascal}Contract) Test{op_pascal}(t *testing.T) {{\n"
        ));
        out.push_str("\tadapter := c.New()\n");

        // Zero-value vars for inputs
        let mut arg_names = Vec::new();
        for input in &op.inputs {
            let var_name = convert(&input.name, Case::Snake);
            let zero = go_zero_value(&input.typ, &defaults, user_type_map);
            out.push_str(&format!("\t{var_name} := {zero}\n"));
            arg_names.push(var_name);
        }

        // Build return vars and call
        let has_error = op
            .outputs
            .iter()
            .any(|o| typemap::is_error_type(&o.typ));
        let non_error_outputs: Vec<_> = op
            .outputs
            .iter()
            .filter(|o| !typemap::is_error_type(&o.typ))
            .collect();

        let mut ret_vars = Vec::new();
        for output in &non_error_outputs {
            ret_vars.push(convert(&output.name, Case::Snake));
        }
        if has_error {
            ret_vars.push("err".to_string());
        }

        let args = arg_names.join(", ");
        if ret_vars.is_empty() {
            out.push_str(&format!("\tadapter.{op_pascal}({args})\n"));
        } else {
            let ret = ret_vars.join(", ");
            out.push_str(&format!("\t{ret} := adapter.{op_pascal}({args})\n"));
        }

        if has_error {
            out.push_str(&format!(
                "\tif err != nil {{ t.Logf(\"{op_pascal} returned error: %v\", err) }}\n"
            ));
        }

        // Suppress unused warnings for non-error return vars
        for v in &non_error_outputs {
            let var_name = convert(&v.name, Case::Snake);
            out.push_str(&format!("\t_ = {var_name}\n"));
        }

        out.push_str("\t_ = adapter\n");
        out.push_str("}\n");
    }

    (path, out)
}

fn go_zero_value(
    typ: &str,
    defaults: &HashMap<&str, &str>,
    user_map: &HashMap<String, String>,
) -> String {
    if typemap::is_error_type(typ) {
        return "nil".to_string();
    }
    if typ.strip_suffix('?').is_some() {
        return "nil".to_string();
    }
    if typ.starts_with("List<") || typ.starts_with("Map<") || typ.starts_with("Set<") {
        return "nil".to_string();
    }
    match typ {
        "String" => "\"\"".to_string(),
        "Int" => "0".to_string(),
        "Float" | "Decimal" => "0.0".to_string(),
        "Bool" => "false".to_string(),
        "Bytes" => "nil".to_string(),
        "DateTime" => "time.Time{}".to_string(),
        "Any" => "nil".to_string(),
        "Unit" => "struct{}{}".to_string(),
        other => {
            let resolved = if let Some(v) = user_map.get(other) {
                v.as_str()
            } else if let Some(v) = defaults.get(other) {
                v
            } else {
                other
            };
            format!("{resolved}{{}}")
        }
    }
}

// ---------------------------------------------------------------------------
// TypeScript
// ---------------------------------------------------------------------------

fn gen_typescript(
    boundary: &Declaration,
    adapters: &[&str],
    layer_dir: &str,
) -> (PathBuf, String) {
    let kebab = to_kebab(&boundary.name);
    let pascal = convert(&boundary.name, Case::Pascal);
    let path = Path::new(layer_dir).join(format!("{kebab}.contract.ts"));

    let adapter_names = adapters.join(", ");

    let mut out = String::new();
    out.push_str(&format!("// Contract tests for {pascal}\n"));
    out.push_str(&format!("// Known adapters: {adapter_names}\n"));
    out.push('\n');
    out.push_str(&format!("export function test{pascal}Contract(\n"));
    out.push_str(&format!("  factory: () => {pascal},\n"));
    out.push_str("  describe: (name: string, fn: () => void) => void,\n");
    out.push_str("  it: (name: string, fn: () => Promise<void>) => void,\n");
    out.push_str(") {\n");
    out.push_str(&format!("  describe(\"{pascal} contract\", () => {{\n"));

    for op in &boundary.ops {
        let camel = convert(&op.name, Case::Camel);
        out.push_str(&format!(
            "    it(\"should implement {camel}\", async () => {{\n"
        ));
        out.push_str("      const adapter = factory();\n");
        out.push_str(&format!(
            "      if (typeof adapter.{camel} !== \"function\") {{\n"
        ));
        out.push_str(&format!(
            "        throw new Error(\"{camel} is not a function\");\n"
        ));
        out.push_str("      }\n");
        out.push_str("    });\n");
    }

    out.push_str("  });\n");
    out.push_str("}\n");

    (path, out)
}

// ---------------------------------------------------------------------------
// Rust
// ---------------------------------------------------------------------------

fn gen_rust(
    boundary: &Declaration,
    adapters: &[&str],
    layer_dir: &str,
    user_type_map: &HashMap<String, String>,
) -> (PathBuf, String) {
    let snake = convert(&boundary.name, Case::Snake);
    let pascal = convert(&boundary.name, Case::Pascal);
    let path = Path::new(layer_dir).join(format!("{snake}_contract.rs"));

    let adapter_names = adapters.join(", ");

    let defaults = typemap::defaults(Language::Rust);

    let mut out = String::new();
    out.push_str(&format!("// Contract tests for {pascal}\n"));
    out.push_str(&format!(
        "// Any type implementing {pascal} must pass these tests.\n"
    ));
    if !adapters.is_empty() {
        out.push_str(&format!("// Known adapters: {adapter_names}\n"));
    }
    out.push('\n');
    out.push_str("#[cfg(test)]\n");
    out.push_str(&format!(
        "pub fn test_{snake}_contract(adapter: &mut impl {pascal}) {{\n"
    ));

    for op in &boundary.ops {
        let snake_op = convert(&op.name, Case::Snake);
        out.push_str(&format!("    // Test: {snake_op}\n"));

        let zero_args: Vec<String> = op
            .inputs
            .iter()
            .map(|input| rust_zero_value(&input.typ, &defaults, user_type_map))
            .collect();

        let args = zero_args.join(", ");
        out.push_str(&format!("    let _ = adapter.{snake_op}({args});\n"));
    }

    out.push_str("}\n");

    (path, out)
}

fn rust_zero_value(
    typ: &str,
    _defaults: &HashMap<&str, &str>,
    _user_map: &HashMap<String, String>,
) -> String {
    if typ.strip_suffix('?').is_some() {
        return "None".to_string();
    }
    if typ.starts_with("Option<") {
        return "None".to_string();
    }
    if typ.starts_with("List<") {
        return "vec![]".to_string();
    }
    if typ.starts_with("Map<") || typ.starts_with("Set<") {
        return "Default::default()".to_string();
    }
    match typ {
        "String" => "String::new()".to_string(),
        "Int" => "0".to_string(),
        "Float" | "Decimal" => "0.0".to_string(),
        "Bool" => "false".to_string(),
        "Bytes" => "vec![]".to_string(),
        "DateTime" => "String::new()".to_string(),
        "Error" => "String::new()".to_string(),
        "Any" => "Default::default()".to_string(),
        "Unit" => "()".to_string(),
        _ => "Default::default()".to_string(),
    }
}

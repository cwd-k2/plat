pub use plat_manifest::naming::convert;
pub use plat_manifest::typemap;
pub use plat_manifest::{Case, DeclKind, Declaration, Field, Language, Manifest, Op};

use std::collections::HashMap;

// ---------------------------------------------------------------------------
// Resolved configuration
// ---------------------------------------------------------------------------

pub struct Config {
    pub language: Language,
    pub layer_dirs: HashMap<String, String>,
    pub user_types: HashMap<String, String>,
    pub default_types: HashMap<&'static str, &'static str>,
    pub go_module: Option<String>,
}

impl Config {
    pub fn new(
        language: Language,
        layer_dirs: HashMap<String, String>,
        user_types: HashMap<String, String>,
        go_module: Option<String>,
    ) -> Self {
        Self {
            language,
            layer_dirs,
            user_types,
            default_types: typemap::defaults(language),
            go_module,
        }
    }

    fn layer_dir(&self, layer: Option<&str>) -> String {
        match layer {
            Some(ly) => self
                .layer_dirs
                .get(ly)
                .cloned()
                .unwrap_or_else(|| ly.to_string()),
            None => self.default_layer_dir(),
        }
    }

    fn default_layer_dir(&self) -> String {
        "domain".to_string()
    }

    fn resolve_type(&self, manifest_type: &str) -> String {
        typemap::resolve(manifest_type, self.language, &self.default_types, &self.user_types)
    }
}

// ---------------------------------------------------------------------------
// Helpers: naming
// ---------------------------------------------------------------------------

fn snake(name: &str) -> String {
    convert(name, Case::Snake)
}

fn pascal(name: &str) -> String {
    convert(name, Case::Pascal)
}

fn camel(name: &str) -> String {
    convert(name, Case::Camel)
}

fn kebab(name: &str) -> String {
    let mut out = String::new();
    for ch in name.chars() {
        if ch == '_' || ch == '-' {
            if !out.is_empty() {
                out.push('-');
            }
        } else if ch.is_uppercase() {
            if !out.is_empty() {
                let prev_lower = out.chars().last().is_some_and(|c| c.is_lowercase());
                if prev_lower {
                    out.push('-');
                }
            }
            out.push(ch.to_ascii_lowercase());
        } else {
            out.push(ch);
        }
    }
    out
}

fn lookup_decl<'a>(name: &str, manifest: &'a Manifest) -> Option<&'a Declaration> {
    manifest.declarations.iter().find(|d| d.name == name)
}

fn has_error_output(op: &Op) -> bool {
    op.outputs.iter().any(|f| typemap::is_error_type(&f.typ))
}

fn non_error_outputs(op: &Op) -> Vec<&Field> {
    op.outputs
        .iter()
        .filter(|f| !typemap::is_error_type(&f.typ))
        .collect()
}

// ---------------------------------------------------------------------------
// Dispatch
// ---------------------------------------------------------------------------

pub fn generate(cfg: &Config, manifest: &Manifest) -> Vec<(String, String)> {
    match cfg.language {
        Language::Go => generate_go(cfg, manifest),
        Language::TypeScript => generate_ts(cfg, manifest),
        Language::Rust => generate_rust(cfg, manifest),
    }
}

// ---------------------------------------------------------------------------
// Go generation
// ---------------------------------------------------------------------------

fn generate_go(cfg: &Config, manifest: &Manifest) -> Vec<(String, String)> {
    let mut files = Vec::new();
    for decl in &manifest.declarations {
        match decl.kind {
            DeclKind::Model => files.extend(go_model(cfg, decl)),
            DeclKind::Boundary => files.extend(go_boundary(cfg, decl)),
            DeclKind::Operation => files.extend(go_operation(cfg, manifest, decl)),
            DeclKind::Adapter => files.extend(go_adapter(cfg, manifest, decl)),
            DeclKind::Compose | DeclKind::Unknown => {}
        }
    }
    files
}

fn go_file_path(cfg: &Config, decl: &Declaration, default_pkg: &str) -> (String, String) {
    let pkg = decl
        .layer
        .as_ref()
        .map(|l| cfg.layer_dir(Some(l)))
        .unwrap_or_else(|| default_pkg.to_string());
    let file = format!("{}/{}.go", pkg, snake(&decl.name));
    (pkg, file)
}

fn go_model(cfg: &Config, decl: &Declaration) -> Vec<(String, String)> {
    let (pkg, file) = go_file_path(cfg, decl, "domain");
    let name = pascal(&decl.name);
    let mut out = String::new();

    out.push_str(&format!("package {pkg}\n"));
    out.push('\n');
    out.push_str(&format!("// {name} — generated from model {}\n", decl.name));
    out.push_str(&format!("type {name} struct {{\n"));
    for field in &decl.fields {
        let fname = pascal(&field.name);
        let ftype = cfg.resolve_type(&field.typ);
        out.push_str(&format!("\t{fname} {ftype}\n"));
    }
    out.push_str("}\n");

    vec![(file, out)]
}

fn go_boundary(cfg: &Config, decl: &Declaration) -> Vec<(String, String)> {
    let (pkg, file) = go_file_path(cfg, decl, "port");
    let name = pascal(&decl.name);
    let mut out = String::new();

    out.push_str(&format!("package {pkg}\n"));
    out.push('\n');
    out.push_str(&format!("// {name} — generated from boundary {}\n", decl.name));
    out.push_str(&format!("type {name} interface {{\n"));
    for op in &decl.ops {
        out.push_str(&format!("\t{}\n", go_op_sig(cfg, op)));
    }
    out.push_str("}\n");

    vec![(file, out)]
}

fn go_op_sig(cfg: &Config, op: &Op) -> String {
    let name = pascal(&op.name);
    let params = go_params(cfg, &op.inputs);
    let returns = go_returns(cfg, op);
    format!("{name}({params}){returns}")
}

fn go_params(cfg: &Config, fields: &[Field]) -> String {
    fields
        .iter()
        .map(|f| format!("{} {}", f.name, cfg.resolve_type(&f.typ)))
        .collect::<Vec<_>>()
        .join(", ")
}

fn go_returns(cfg: &Config, op: &Op) -> String {
    if op.outputs.is_empty() {
        return String::new();
    }
    let has_err = has_error_output(op);
    let non_err = non_error_outputs(op);
    match (non_err.len(), has_err) {
        (0, true) => " error".to_string(),
        (1, true) => format!(" ({}, error)", cfg.resolve_type(&non_err[0].typ)),
        (_, true) => {
            let types: Vec<String> = non_err.iter().map(|f| cfg.resolve_type(&f.typ)).collect();
            format!(" ({}, error)", types.join(", "))
        }
        _ => {
            let types: Vec<String> =
                op.outputs.iter().map(|f| cfg.resolve_type(&f.typ)).collect();
            format!(" ({})", types.join(", "))
        }
    }
}

fn go_operation(cfg: &Config, manifest: &Manifest, decl: &Declaration) -> Vec<(String, String)> {
    let pkg = decl
        .layer
        .as_ref()
        .map(|l| cfg.layer_dir(Some(l)))
        .unwrap_or_else(|| "usecase".to_string());
    let file = format!("{}/{}.go", pkg, snake(&decl.name));
    let name = pascal(&decl.name);

    let dep_decls: Vec<&Declaration> = decl
        .needs
        .iter()
        .filter_map(|n| lookup_decl(n, manifest))
        .collect();

    let mut out = String::new();
    out.push_str(&format!("package {pkg}\n"));
    out.push('\n');
    out.push_str(&format!(
        "// {name} — generated from operation {}\n",
        decl.name
    ));

    out.push_str(&format!("type {name} struct {{\n"));
    for dd in &dep_decls {
        let field_name = camel(&dd.name);
        let field_type = go_qualified_port(cfg, dd);
        out.push_str(&format!("\t{field_name} {field_type}\n"));
    }
    out.push_str("}\n");
    out.push('\n');

    let ctor_params: Vec<String> = dep_decls
        .iter()
        .map(|dd| format!("{} {}", camel(&dd.name), go_qualified_port(cfg, dd)))
        .collect();
    out.push_str(&format!(
        "func New{name}({}) *{name} {{\n",
        ctor_params.join(", ")
    ));
    out.push_str(&format!("\treturn &{name}{{\n"));
    for dd in &dep_decls {
        let field_name = camel(&dd.name);
        out.push_str(&format!("\t\t{field_name}: {field_name},\n"));
    }
    out.push_str("\t}\n");
    out.push_str("}\n");
    out.push('\n');

    let execute_params = go_execute_params(cfg, decl);
    let execute_returns = go_execute_returns(cfg, decl);
    out.push_str(&format!(
        "func (uc *{name}) Execute({execute_params}) {execute_returns} {{\n"
    ));
    out.push_str(&format!("\tpanic(\"TODO: implement {name}\")\n"));
    out.push_str("}\n");

    vec![(file, out)]
}

fn go_execute_params(cfg: &Config, decl: &Declaration) -> String {
    let inputs: Vec<&Field> = decl.ops.iter().flat_map(|op| &op.inputs).collect();
    inputs
        .iter()
        .map(|f| format!("{} {}", f.name, cfg.resolve_type(&f.typ)))
        .collect::<Vec<_>>()
        .join(", ")
}

fn go_execute_returns(cfg: &Config, decl: &Declaration) -> String {
    let outputs: Vec<&Field> = decl.ops.iter().flat_map(|op| &op.outputs).collect();
    if outputs.is_empty() {
        return String::new();
    }
    let has_err = outputs.iter().any(|f| typemap::is_error_type(&f.typ));
    let non_err: Vec<&&Field> = outputs
        .iter()
        .filter(|f| !typemap::is_error_type(&f.typ))
        .collect();
    match (non_err.len(), has_err) {
        (0, true) => "error".to_string(),
        (1, true) => format!("({}, error)", cfg.resolve_type(&non_err[0].typ)),
        (_, true) => {
            let types: Vec<String> = non_err.iter().map(|f| cfg.resolve_type(&f.typ)).collect();
            format!("({}, error)", types.join(", "))
        }
        _ => {
            let types: Vec<String> =
                outputs.iter().map(|f| cfg.resolve_type(&f.typ)).collect();
            format!("({})", types.join(", "))
        }
    }
}

fn go_qualified_port(cfg: &Config, decl: &Declaration) -> String {
    let pkg = decl
        .layer
        .as_ref()
        .map(|l| cfg.layer_dir(Some(l)))
        .unwrap_or_else(|| "port".to_string());
    format!("{}.{}", pkg, pascal(&decl.name))
}

fn go_adapter(cfg: &Config, manifest: &Manifest, decl: &Declaration) -> Vec<(String, String)> {
    let pkg = decl
        .layer
        .as_ref()
        .map(|l| cfg.layer_dir(Some(l)))
        .unwrap_or_else(|| "adapter".to_string());
    let file = format!("{}/{}.go", pkg, snake(&decl.name));
    let name = pascal(&decl.name);

    let mut out = String::new();
    out.push_str(&format!("package {pkg}\n"));
    out.push('\n');
    out.push_str(&format!(
        "// {name} — generated from adapter {}\n",
        decl.name
    ));

    if let Some(impl_name) = &decl.implements {
        if let Some(bnd) = lookup_decl(impl_name, manifest) {
            out.push_str(&format!("// implements {}\n", bnd.name));
        }
    }

    out.push_str(&format!("type {name} struct {{\n"));
    for inject in &decl.injects {
        let fname = pascal(&inject.name);
        let ftype = cfg.resolve_type(&inject.typ);
        out.push_str(&format!("\t{fname} {ftype}\n"));
    }
    out.push_str("}\n");

    vec![(file, out)]
}

// ---------------------------------------------------------------------------
// TypeScript generation
// ---------------------------------------------------------------------------

fn generate_ts(cfg: &Config, manifest: &Manifest) -> Vec<(String, String)> {
    let mut files = Vec::new();
    for decl in &manifest.declarations {
        match decl.kind {
            DeclKind::Model => files.extend(ts_model(cfg, decl)),
            DeclKind::Boundary => files.extend(ts_boundary(cfg, decl)),
            DeclKind::Operation => files.extend(ts_operation(cfg, manifest, decl)),
            DeclKind::Adapter => files.extend(ts_adapter(cfg, manifest, decl)),
            DeclKind::Compose | DeclKind::Unknown => {}
        }
    }
    files
}

fn ts_file_path(cfg: &Config, decl: &Declaration, default_dir: &str) -> String {
    let dir = decl
        .layer
        .as_ref()
        .map(|l| cfg.layer_dir(Some(l)))
        .unwrap_or_else(|| default_dir.to_string());
    format!("{}/{}.ts", dir, kebab(&decl.name))
}

fn ts_model(cfg: &Config, decl: &Declaration) -> Vec<(String, String)> {
    let file = ts_file_path(cfg, decl, "domain");
    let name = &decl.name;
    let mut out = String::new();

    out.push_str(&format!("// Generated from model {name}\n"));
    out.push_str(&format!("export interface {name} {{\n"));
    for field in &decl.fields {
        let fname = camel(&field.name);
        let ftype = cfg.resolve_type(&field.typ);
        out.push_str(&format!("  {fname}: {ftype};\n"));
    }
    out.push_str("}\n");

    vec![(file, out)]
}

fn ts_boundary(cfg: &Config, decl: &Declaration) -> Vec<(String, String)> {
    let file = ts_file_path(cfg, decl, "port");
    let name = &decl.name;
    let mut out = String::new();

    out.push_str(&format!("// Generated from boundary {name}\n"));
    out.push_str(&format!("export interface {name} {{\n"));
    for op in &decl.ops {
        out.push_str(&format!("  {};\n", ts_op_sig(cfg, op)));
    }
    out.push_str("}\n");

    vec![(file, out)]
}

fn ts_op_sig(cfg: &Config, op: &Op) -> String {
    let name = camel(&op.name);
    let params = ts_params(cfg, &op.inputs);
    let ret = ts_return_type(cfg, op);
    format!("{name}({params}): Promise<{ret}>")
}

fn ts_params(cfg: &Config, fields: &[Field]) -> String {
    fields
        .iter()
        .map(|f| format!("{}: {}", camel(&f.name), cfg.resolve_type(&f.typ)))
        .collect::<Vec<_>>()
        .join(", ")
}

fn ts_return_type(cfg: &Config, op: &Op) -> String {
    let non_err = non_error_outputs(op);
    match non_err.len() {
        0 => "void".to_string(),
        1 => cfg.resolve_type(&non_err[0].typ),
        _ => {
            let parts: Vec<String> = non_err
                .iter()
                .map(|f| format!("{}: {}", camel(&f.name), cfg.resolve_type(&f.typ)))
                .collect();
            format!("{{ {} }}", parts.join("; "))
        }
    }
}

fn ts_operation(cfg: &Config, manifest: &Manifest, decl: &Declaration) -> Vec<(String, String)> {
    let file = ts_file_path(cfg, decl, "application");
    let name = &decl.name;

    let dep_decls: Vec<&Declaration> = decl
        .needs
        .iter()
        .filter_map(|n| lookup_decl(n, manifest))
        .collect();

    let inputs: Vec<&Field> = decl.ops.iter().flat_map(|op| &op.inputs).collect();
    let ret = ts_operation_return_type(cfg, decl);

    let mut out = String::new();
    out.push_str(&format!("// Generated from operation {name}\n"));
    out.push('\n');
    out.push_str(&format!("export class {name} {{\n"));
    out.push_str("  constructor(\n");
    for dd in &dep_decls {
        out.push_str(&format!(
            "    private {}: {},\n",
            camel(&dd.name),
            dd.name
        ));
    }
    out.push_str("  ) {}\n");
    out.push('\n');
    out.push_str("  async execute(input: {\n");
    for f in &inputs {
        out.push_str(&format!(
            "    {}: {};\n",
            camel(&f.name),
            cfg.resolve_type(&f.typ)
        ));
    }
    out.push_str(&format!("  }}): Promise<{ret}> {{\n"));
    out.push_str(&format!(
        "    throw new Error(\"TODO: implement {name}\");\n"
    ));
    out.push_str("  }\n");
    out.push_str("}\n");

    vec![(file, out)]
}

fn ts_operation_return_type(cfg: &Config, decl: &Declaration) -> String {
    let outputs: Vec<&Field> = decl.ops.iter().flat_map(|op| &op.outputs).collect();
    let non_err: Vec<&&Field> = outputs
        .iter()
        .filter(|f| !typemap::is_error_type(&f.typ))
        .collect();
    match non_err.len() {
        0 => "void".to_string(),
        1 => cfg.resolve_type(&non_err[0].typ),
        _ => {
            let parts: Vec<String> = non_err
                .iter()
                .map(|f| format!("{}: {}", camel(&f.name), cfg.resolve_type(&f.typ)))
                .collect();
            format!("{{ {} }}", parts.join("; "))
        }
    }
}

fn ts_adapter(cfg: &Config, manifest: &Manifest, decl: &Declaration) -> Vec<(String, String)> {
    let file = ts_file_path(cfg, decl, "adapter");
    let name = &decl.name;

    let impl_clause = decl
        .implements
        .as_ref()
        .and_then(|bn| lookup_decl(bn, manifest))
        .map(|bnd| format!(" implements {}", bnd.name))
        .unwrap_or_default();

    let mut out = String::new();
    out.push_str(&format!("// Generated from adapter {name}\n"));
    out.push('\n');
    out.push_str(&format!("export class {name}{impl_clause} {{\n"));
    out.push_str("  constructor(\n");
    for inject in &decl.injects {
        out.push_str(&format!(
            "    private {}: {},\n",
            camel(&inject.name),
            cfg.resolve_type(&inject.typ)
        ));
    }
    out.push_str("  ) {}\n");

    if let Some(bnd) = decl
        .implements
        .as_ref()
        .and_then(|bn| lookup_decl(bn, manifest))
    {
        for op in &bnd.ops {
            out.push('\n');
            let params = ts_params(cfg, &op.inputs);
            let ret = ts_return_type(cfg, op);
            out.push_str(&format!(
                "  async {}({params}): Promise<{ret}> {{\n",
                camel(&op.name)
            ));
            out.push_str(&format!(
                "    throw new Error(\"TODO: implement {}\");\n",
                op.name
            ));
            out.push_str("  }\n");
        }
    }

    out.push_str("}\n");

    vec![(file, out)]
}

// ---------------------------------------------------------------------------
// Rust generation
// ---------------------------------------------------------------------------

fn generate_rust(cfg: &Config, manifest: &Manifest) -> Vec<(String, String)> {
    let mut files = Vec::new();
    let mut layer_decls: HashMap<String, Vec<&Declaration>> = HashMap::new();

    for decl in &manifest.declarations {
        if matches!(decl.kind, DeclKind::Compose | DeclKind::Unknown) {
            continue;
        }
        let dir = rust_layer_dir(cfg, decl);
        layer_decls.entry(dir).or_default().push(decl);

        match decl.kind {
            DeclKind::Model => files.extend(rust_model(cfg, decl)),
            DeclKind::Boundary => files.extend(rust_boundary(cfg, decl)),
            DeclKind::Operation => files.extend(rust_operation(cfg, manifest, decl)),
            DeclKind::Adapter => files.extend(rust_adapter(cfg, manifest, decl)),
            DeclKind::Compose | DeclKind::Unknown => {}
        }
    }

    for (dir, decls) in &layer_decls {
        let mods: Vec<String> = decls
            .iter()
            .map(|d| format!("pub mod {};", snake(&d.name)))
            .collect();
        files.push((format!("{dir}/mod.rs"), mods.join("\n") + "\n"));
    }

    files
}

fn rust_layer_dir(cfg: &Config, decl: &Declaration) -> String {
    decl.layer
        .as_ref()
        .map(|l| cfg.layer_dir(Some(l)))
        .unwrap_or_else(|| "domain".to_string())
}

fn rust_file_path(cfg: &Config, decl: &Declaration, default_dir: &str) -> String {
    let dir = decl
        .layer
        .as_ref()
        .map(|l| cfg.layer_dir(Some(l)))
        .unwrap_or_else(|| default_dir.to_string());
    format!("{}/{}.rs", dir, snake(&decl.name))
}

fn rust_model(cfg: &Config, decl: &Declaration) -> Vec<(String, String)> {
    let file = rust_file_path(cfg, decl, "domain");
    let name = &decl.name;
    let mut out = String::new();

    out.push_str(&format!("// Generated from model {name}\n"));
    out.push('\n');
    out.push_str("#[derive(Debug, Clone)]\n");
    out.push_str(&format!("pub struct {name} {{\n"));
    for field in &decl.fields {
        let fname = snake(&field.name);
        let ftype = cfg.resolve_type(&field.typ);
        out.push_str(&format!("    pub {fname}: {ftype},\n"));
    }
    out.push_str("}\n");

    vec![(file, out)]
}

fn rust_boundary(cfg: &Config, decl: &Declaration) -> Vec<(String, String)> {
    let file = rust_file_path(cfg, decl, "domain");
    let name = &decl.name;
    let mut out = String::new();

    out.push_str(&format!("// Generated from boundary {name}\n"));
    out.push('\n');
    out.push_str(&format!("pub trait {name} {{\n"));
    for op in &decl.ops {
        out.push_str(&format!("    {};\n", rust_trait_method(cfg, op)));
    }
    out.push_str("}\n");

    vec![(file, out)]
}

fn rust_trait_method(cfg: &Config, op: &Op) -> String {
    let name = snake(&op.name);
    let mut params = vec!["&mut self".to_string()];
    for f in &op.inputs {
        params.push(format!(
            "{}: {}",
            snake(&f.name),
            cfg.resolve_type(&f.typ)
        ));
    }
    let ret = rust_return_type(cfg, op);
    format!("fn {name}({}) -> {ret}", params.join(", "))
}

fn rust_return_type(cfg: &Config, op: &Op) -> String {
    if op.outputs.is_empty() {
        return "()".to_string();
    }
    let has_err = has_error_output(op);
    let non_err = non_error_outputs(op);
    match (non_err.len(), has_err) {
        (0, true) => "Result<(), String>".to_string(),
        (1, true) => format!("Result<{}, String>", cfg.resolve_type(&non_err[0].typ)),
        (_, true) => {
            let types: Vec<String> = non_err.iter().map(|f| cfg.resolve_type(&f.typ)).collect();
            format!("Result<({}), String>", types.join(", "))
        }
        (1, false) => cfg.resolve_type(&non_err[0].typ),
        _ => {
            let types: Vec<String> =
                op.outputs.iter().map(|f| cfg.resolve_type(&f.typ)).collect();
            format!("({})", types.join(", "))
        }
    }
}

fn rust_operation(cfg: &Config, manifest: &Manifest, decl: &Declaration) -> Vec<(String, String)> {
    let file = rust_file_path(cfg, decl, "application");
    let name = &decl.name;

    let dep_decls: Vec<&Declaration> = decl
        .needs
        .iter()
        .filter_map(|n| lookup_decl(n, manifest))
        .collect();

    let inputs: Vec<&Field> = decl.ops.iter().flat_map(|op| &op.inputs).collect();
    let outputs: Vec<&Field> = decl.ops.iter().flat_map(|op| &op.outputs).collect();
    let ret = rust_fn_return_type(cfg, &outputs);

    let mut out = String::new();
    out.push_str(&format!("// Generated from operation {name}\n"));
    out.push('\n');
    out.push_str("pub fn execute(\n");
    for dd in &dep_decls {
        out.push_str(&format!(
            "    {}: &mut impl {},\n",
            snake(&dd.name),
            dd.name
        ));
    }
    for f in &inputs {
        out.push_str(&format!(
            "    {}: {},\n",
            snake(&f.name),
            cfg.resolve_type(&f.typ)
        ));
    }
    out.push_str(&format!(") -> {ret} {{\n"));
    out.push_str(&format!("    todo!(\"implement {name}\")\n"));
    out.push_str("}\n");

    vec![(file, out)]
}

fn rust_fn_return_type(cfg: &Config, outputs: &[&Field]) -> String {
    if outputs.is_empty() {
        return "()".to_string();
    }
    let has_err = outputs.iter().any(|f| typemap::is_error_type(&f.typ));
    let non_err: Vec<&&Field> = outputs
        .iter()
        .filter(|f| !typemap::is_error_type(&f.typ))
        .collect();
    match (non_err.len(), has_err) {
        (0, true) => "Result<(), String>".to_string(),
        (1, true) => format!("Result<{}, String>", cfg.resolve_type(&non_err[0].typ)),
        (_, true) => {
            let types: Vec<String> = non_err.iter().map(|f| cfg.resolve_type(&f.typ)).collect();
            format!("Result<({}), String>", types.join(", "))
        }
        (1, false) => cfg.resolve_type(&non_err[0].typ),
        _ => {
            let types: Vec<String> =
                outputs.iter().map(|f| cfg.resolve_type(&f.typ)).collect();
            format!("({})", types.join(", "))
        }
    }
}

fn rust_adapter(cfg: &Config, manifest: &Manifest, decl: &Declaration) -> Vec<(String, String)> {
    let file = rust_file_path(cfg, decl, "infrastructure");
    let name = &decl.name;
    let mut out = String::new();

    out.push_str(&format!("// Generated from adapter {name}\n"));
    out.push('\n');
    out.push_str(&format!("pub struct {name} {{\n"));
    for inject in &decl.injects {
        let fname = snake(&inject.name);
        let ftype = cfg.resolve_type(&inject.typ);
        out.push_str(&format!("    pub {fname}: {ftype},\n"));
    }
    out.push_str("}\n");

    if let Some(bnd) = decl
        .implements
        .as_ref()
        .and_then(|bn| lookup_decl(bn, manifest))
    {
        out.push('\n');
        out.push_str(&format!("impl {} for {name} {{\n", bnd.name));
        for op in &bnd.ops {
            let method_name = snake(&op.name);
            let mut params = vec!["&mut self".to_string()];
            for f in &op.inputs {
                params.push(format!(
                    "{}: {}",
                    snake(&f.name),
                    cfg.resolve_type(&f.typ)
                ));
            }
            let ret = rust_return_type(cfg, op);
            out.push_str(&format!(
                "    fn {method_name}({}) -> {ret} {{\n",
                params.join(", ")
            ));
            out.push_str(&format!("        todo!(\"implement {}\")\n", op.name));
            out.push_str("    }\n");
        }
        out.push_str("}\n");
    }

    vec![(file, out)]
}

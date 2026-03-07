use std::collections::HashMap;

use crate::Language;

/// Build the default type mapping for a language.
pub fn defaults(lang: Language) -> HashMap<&'static str, &'static str> {
    let mut m = HashMap::new();
    match lang {
        Language::Go => {
            m.insert("String", "string");
            m.insert("Int", "int");
            m.insert("Float", "float64");
            m.insert("Decimal", "float64");
            m.insert("Bool", "bool");
            m.insert("Unit", "struct{}");
            m.insert("Bytes", "[]byte");
            m.insert("DateTime", "time.Time");
            m.insert("Any", "interface{}");
            m.insert("Error", "error");
        }
        Language::TypeScript => {
            m.insert("String", "string");
            m.insert("Int", "number");
            m.insert("Float", "number");
            m.insert("Decimal", "number");
            m.insert("Bool", "boolean");
            m.insert("Unit", "void");
            m.insert("Bytes", "Uint8Array");
            m.insert("DateTime", "Date");
            m.insert("Any", "any");
            m.insert("Error", "Error");
        }
        Language::Rust => {
            m.insert("String", "String");
            m.insert("Int", "i64");
            m.insert("Float", "f64");
            m.insert("Decimal", "f64");
            m.insert("Bool", "bool");
            m.insert("Unit", "()");
            m.insert("Bytes", "Vec<u8>");
            m.insert("DateTime", "DateTime<Utc>");
            m.insert("Any", "Box<dyn Any>");
            m.insert("Error", "String");
        }
    }
    m
}

/// Resolve a manifest type string to the expected source type string.
pub fn resolve(
    manifest_type: &str,
    lang: Language,
    default_map: &HashMap<&str, &str>,
    user_map: &HashMap<String, String>,
) -> String {
    // Nullable shorthand: T?
    if let Some(inner) = manifest_type.strip_suffix('?') {
        let resolved_inner = resolve(inner, lang, default_map, user_map);
        return wrap_nullable(lang, &resolved_inner);
    }

    // Generic: Name<Args...>
    if let Some(pos) = manifest_type.find('<') {
        let name = &manifest_type[..pos];
        let args_str = &manifest_type[pos + 1..manifest_type.len() - 1];
        let args: Vec<String> = split_generic_args(args_str)
            .iter()
            .map(|a| resolve(a.trim(), lang, default_map, user_map))
            .collect();

        return match name {
            "List" => wrap_list(lang, &args[0]),
            "Map" => wrap_map(lang, &args[0], &args[1]),
            "Option" => wrap_nullable(lang, &args[0]),
            "Set" => wrap_set(lang, &args[0]),
            "Result" => wrap_result(
                lang,
                &args[0],
                args.get(1).map(|s| s.as_str()).unwrap_or("String"),
            ),
            "Stream" => wrap_stream(lang, &args[0]),
            _ => format!("{}<{}>", name, args.join(", ")),
        };
    }

    // User overrides take precedence
    if let Some(v) = user_map.get(manifest_type) {
        return v.clone();
    }
    // Language defaults
    if let Some(v) = default_map.get(manifest_type) {
        return v.to_string();
    }
    // User-defined type: pass through
    manifest_type.to_string()
}

pub fn split_generic_args(s: &str) -> Vec<&str> {
    let mut result = Vec::new();
    let mut depth = 0;
    let mut start = 0;
    for (i, ch) in s.char_indices() {
        match ch {
            '<' => depth += 1,
            '>' => depth -= 1,
            ',' if depth == 0 => {
                result.push(&s[start..i]);
                start = i + 1;
            }
            _ => {}
        }
    }
    result.push(&s[start..]);
    result
}

fn wrap_list(lang: Language, inner: &str) -> String {
    match lang {
        Language::Go => format!("[]{inner}"),
        Language::TypeScript => format!("{inner}[]"),
        Language::Rust => format!("Vec<{inner}>"),
    }
}

fn wrap_map(lang: Language, key: &str, val: &str) -> String {
    match lang {
        Language::Go => format!("map[{key}]{val}"),
        Language::TypeScript => format!("Map<{key}, {val}>"),
        Language::Rust => format!("HashMap<{key}, {val}>"),
    }
}

fn wrap_nullable(lang: Language, inner: &str) -> String {
    match lang {
        Language::Go => format!("*{inner}"),
        Language::TypeScript => format!("{inner} | null"),
        Language::Rust => format!("Option<{inner}>"),
    }
}

fn wrap_set(lang: Language, inner: &str) -> String {
    match lang {
        Language::Go => format!("map[{inner}]struct{{}}"),
        Language::TypeScript => format!("Set<{inner}>"),
        Language::Rust => format!("HashSet<{inner}>"),
    }
}

fn wrap_result(lang: Language, ok: &str, err: &str) -> String {
    match lang {
        Language::Go => ok.to_string(),
        Language::TypeScript => ok.to_string(),
        Language::Rust => format!("Result<{ok}, {err}>"),
    }
}

fn wrap_stream(lang: Language, inner: &str) -> String {
    match lang {
        Language::Go => format!("chan {inner}"),
        Language::TypeScript => format!("AsyncIterable<{inner}>"),
        Language::Rust => format!("Stream<{inner}>"),
    }
}

/// Check if a manifest type is `Error`.
pub fn is_error_type(manifest_type: &str) -> bool {
    manifest_type == "Error"
}

const BUILTINS: &[&str] = &[
    "String", "Int", "Float", "Decimal", "Bool", "Unit", "Bytes", "DateTime", "Any", "Error",
    "List", "Map", "Option", "Set", "Result", "Stream",
];

/// Extract all user-defined type names referenced in a manifest type expression.
pub fn extract_type_refs(manifest_type: &str) -> Vec<&str> {
    let mut refs = Vec::new();
    collect_type_refs(manifest_type, &mut refs);
    refs
}

fn collect_type_refs<'a>(typ: &'a str, refs: &mut Vec<&'a str>) {
    let typ = typ.trim();
    if typ.is_empty() {
        return;
    }

    if let Some(inner) = typ.strip_suffix('?') {
        collect_type_refs(inner, refs);
        return;
    }

    if let Some(pos) = typ.find('<') {
        let name = &typ[..pos];
        if !BUILTINS.contains(&name) {
            refs.push(name);
        }
        let args_str = &typ[pos + 1..typ.len() - 1];
        for arg in split_generic_args(args_str) {
            collect_type_refs(arg.trim(), refs);
        }
        return;
    }

    if !BUILTINS.contains(&typ) {
        refs.push(typ);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn go_primitives() {
        let dm = defaults(Language::Go);
        let um = HashMap::new();
        assert_eq!(resolve("String", Language::Go, &dm, &um), "string");
        assert_eq!(resolve("Int", Language::Go, &dm, &um), "int");
        assert_eq!(resolve("Bool", Language::Go, &dm, &um), "bool");
    }

    #[test]
    fn go_generics() {
        let dm = defaults(Language::Go);
        let um = HashMap::new();
        assert_eq!(resolve("List<String>", Language::Go, &dm, &um), "[]string");
        assert_eq!(
            resolve("Map<String, Int>", Language::Go, &dm, &um),
            "map[string]int"
        );
    }

    #[test]
    fn nullable_shorthand() {
        let dm = defaults(Language::Go);
        let um = HashMap::new();
        assert_eq!(resolve("String?", Language::Go, &dm, &um), "*string");
    }

    #[test]
    fn user_override() {
        let dm = defaults(Language::Go);
        let mut um = HashMap::new();
        um.insert("UUID".to_string(), "uuid.UUID".to_string());
        assert_eq!(resolve("UUID", Language::Go, &dm, &um), "uuid.UUID");
    }

    #[test]
    fn rust_result() {
        let dm = defaults(Language::Rust);
        let um = HashMap::new();
        assert_eq!(
            resolve("Result<String, Error>", Language::Rust, &dm, &um),
            "Result<String, String>"
        );
    }

    #[test]
    fn passthrough_user_type() {
        let dm = defaults(Language::Go);
        let um = HashMap::new();
        assert_eq!(resolve("Order", Language::Go, &dm, &um), "Order");
    }
}

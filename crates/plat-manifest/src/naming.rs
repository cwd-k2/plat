use crate::Case;

/// Split a PascalCase or camelCase identifier into words.
fn split_words(s: &str) -> Vec<String> {
    let mut words = Vec::new();
    let mut current = String::new();
    for ch in s.chars() {
        if ch == '_' || ch == '-' {
            if !current.is_empty() {
                words.push(current);
                current = String::new();
            }
        } else if ch.is_uppercase() && !current.is_empty() {
            let prev_lower = current.chars().last().is_some_and(|c| c.is_lowercase());
            if prev_lower {
                words.push(current);
                current = String::new();
            }
            current.push(ch);
        } else {
            current.push(ch);
        }
    }
    if !current.is_empty() {
        words.push(current);
    }
    words
}

pub fn convert(name: &str, target: Case) -> String {
    let words = split_words(name);
    if words.is_empty() {
        return name.to_string();
    }
    match target {
        Case::Pascal => words
            .iter()
            .map(|w| {
                let mut chars = w.chars();
                match chars.next() {
                    Some(c) => c.to_uppercase().to_string() + &chars.as_str().to_lowercase(),
                    None => String::new(),
                }
            })
            .collect(),
        Case::Camel => words
            .iter()
            .enumerate()
            .map(|(i, w)| {
                let mut chars = w.chars();
                match chars.next() {
                    Some(c) if i == 0 => {
                        c.to_lowercase().to_string() + &chars.as_str().to_lowercase()
                    }
                    Some(c) => c.to_uppercase().to_string() + &chars.as_str().to_lowercase(),
                    None => String::new(),
                }
            })
            .collect(),
        Case::Snake => words
            .iter()
            .map(|w| w.to_lowercase())
            .collect::<Vec<_>>()
            .join("_"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pascal_to_snake() {
        assert_eq!(convert("PlaceOrder", Case::Snake), "place_order");
        assert_eq!(convert("OrderRepository", Case::Snake), "order_repository");
    }

    #[test]
    fn pascal_to_camel() {
        assert_eq!(convert("PlaceOrder", Case::Camel), "placeOrder");
        assert_eq!(convert("GetOrder", Case::Camel), "getOrder");
    }

    #[test]
    fn pascal_identity() {
        assert_eq!(convert("PlaceOrder", Case::Pascal), "PlaceOrder");
    }

    #[test]
    fn snake_to_pascal() {
        assert_eq!(convert("place_order", Case::Pascal), "PlaceOrder");
    }

    #[test]
    fn single_word() {
        assert_eq!(convert("Order", Case::Snake), "order");
        assert_eq!(convert("Order", Case::Camel), "order");
        assert_eq!(convert("Order", Case::Pascal), "Order");
    }
}

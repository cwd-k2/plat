use serde::Deserialize;

#[derive(Debug, Deserialize, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Language {
    Go,
    TypeScript,
    Rust,
}

impl Language {
    pub fn extension(self) -> &'static str {
        match self {
            Self::Go => "go",
            Self::TypeScript => "ts",
            Self::Rust => "rs",
        }
    }

    pub fn default_field_case(self) -> Case {
        match self {
            Self::Go => Case::Pascal,
            Self::TypeScript => Case::Camel,
            Self::Rust => Case::Snake,
        }
    }

    pub fn default_method_case(self) -> Case {
        match self {
            Self::Go => Case::Pascal,
            Self::TypeScript => Case::Camel,
            Self::Rust => Case::Snake,
        }
    }
}

impl std::fmt::Display for Language {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Go => write!(f, "go"),
            Self::TypeScript => write!(f, "typescript"),
            Self::Rust => write!(f, "rust"),
        }
    }
}

#[derive(Debug, Deserialize, Clone, Copy, PartialEq, Eq)]
pub enum Case {
    #[serde(rename = "PascalCase")]
    Pascal,
    #[serde(rename = "camelCase")]
    Camel,
    #[serde(rename = "snake_case")]
    Snake,
}

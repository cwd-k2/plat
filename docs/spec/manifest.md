# Manifest Schema Specification

plat manifest は Haskell（生成側）と Rust ツール群（消費側）の間の **唯一の契約** である。
このドキュメントが manifest JSON format の正式仕様となる。

## Overview

```
Architecture (Haskell)
    │
    ▼
manifest :: Architecture -> Manifest
    │
    ▼
renderManifest :: Manifest -> Text (JSON)
    │
    ▼
┌───────────────┐
│ manifest.json │  ← single source of truth for Rust tools
└───────┬───────┘
        │
   ┌────┼────┬──────────┐
   ▼    ▼    ▼          ▼
verify  skeleton  contract  deprules
```

## Schema Version

現在: `"0.6"`

`schema_version` フィールドは manifest format のバージョンを示す。
ライブラリバージョンとは独立。format に破壊的変更がある場合にのみインクリメントする。

## Top-Level Structure

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `schema_version` | string | yes | Schema version (`"0.6"`) |
| `name` | string | yes | Architecture name |
| `layers` | Layer[] | yes | Layer definitions |
| `type_aliases` | TypeAlias[] | no (default: []) | Type alias definitions |
| `custom_types` | string[] | no (default: []) | Registered type names (`registerType`) |
| `declarations` | Declaration[] | yes | All declarations |
| `bindings` | Binding[] | no (default: []) | Boundary-Adapter bindings (extracted from Compose) |
| `constraints` | Constraint[] | no (default: []) | Architecture-level constraints |
| `relations` | Relation[] | no (default: []) | Explicit relations (`relate`) |
| `meta` | object | no (default: {}) | Architecture-level metadata |

## Layer

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | yes | Layer name |
| `depends` | string[] | no (default: []) | Names of layers this layer depends on |

## TypeAlias

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | yes | Alias name |
| `type` | string | yes | Target type expression (rendered) |

## Declaration

すべての DeclKind が同じフラット構造を共有する。kind に応じて使用されるフィールドが異なる。

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | yes | Declaration name |
| `kind` | string | yes | `"model"` / `"boundary"` / `"operation"` / `"adapter"` / `"compose"` |
| `layer` | string? | no | Layer name (Compose は null) |
| `paths` | string[] | no (default: []) | Associated file paths |
| `fields` | Field[] | no (default: []) | Model fields |
| `ops` | Op[] | no (default: []) | Boundary operations |
| `inputs` | Field[] | no (default: []) | Operation inputs |
| `outputs` | Field[] | no (default: []) | Operation outputs |
| `needs` | string[] | no (default: []) | Referenced boundary names |
| `implements` | string? | no | Implemented boundary name |
| `injects` | Field[] | no (default: []) | Adapter injected dependencies |
| `entries` | string[] | no (default: []) | Compose entry point names |
| `meta` | object | no (default: {}) | Declaration-level metadata |

### kind ごとの使用フィールド

|            | fields | ops | inputs | outputs | needs | implements | injects | entries |
|------------|:------:|:---:|:------:|:-------:|:-----:|:----------:|:-------:|:-------:|
| model      |   o    |     |        |         |       |            |         |         |
| boundary   |        |  o  |        |         |       |            |         |         |
| operation  |        |     |   o    |    o    |   o   |            |         |         |
| adapter    |        |     |        |         |       |     o      |    o    |         |
| compose    |        |     |        |         |       |            |         |    o    |

`paths` と `meta` は全 kind で使用可能。

## Field

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | yes | Field name |
| `type` | string | yes | Type expression (rendered) |

## Op

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | yes | Operation name |
| `inputs` | Field[] | no (default: []) | Input parameters |
| `outputs` | Field[] | no (default: []) | Output parameters |

## Binding

Compose 宣言内の `bind` から抽出される。

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `boundary` | string | yes | Boundary name |
| `adapter` | string | yes | Adapter name |

## Constraint

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | yes | Constraint name |
| `description` | string | yes | Human-readable description |

## Relation

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `kind` | string | yes | Relation kind (e.g., `"needs"`, `"implements"`) |
| `source` | string | yes | Source declaration name |
| `target` | string | yes | Target declaration name |
| `meta` | object | no (default: {}) | Relation metadata |

## Type Expression Format

`type` フィールドの文字列は `renderTypeExpr` で生成される言語非依存の表現。

| Pattern | Example | Description |
|---------|---------|-------------|
| Builtin | `"String"`, `"Int"`, `"Decimal"` | 組み込み型 |
| Reference | `"Order"`, `"UUID"` | 宣言名 or カスタム型名 |
| Generic | `"List<Order>"`, `"Map<String, Int>"` | ジェネリック型 |
| Nullable | `"String?"` | null 許容型 |
| External | `"*sql.DB"` | 外部型 (TExt) — 文字列表現は TRef と同じ |

**注意**: manifest の type 文字列では TExt と TRef の区別がつかない。
外部型 (`ext`) かカスタム型 (`customType`) かは `custom_types` フィールドと照合して判別する。

## Meta Format

`meta` フィールドは JSON object (`{ "key": "value" }`) としてシリアライズされる。
キーの命名規約: `"plat-{extension}:{key}"` (例: `"plat-ddd:kind"`)。

## Compatibility

- 未知のフィールドは無視する (forward compatibility)
- 配列フィールドが欠落した場合は空配列として扱う
- `meta` フィールドが欠落した場合は空 object として扱う
- `schema_version` が欠落した場合は `"0.6"` として扱う (旧 manifest との互換)

## Implementations

| Language | Module / Crate | Role |
|----------|---------------|------|
| Haskell | `Plat.Verify.Manifest` | 生成 + round-trip |
| Rust | `plat-manifest` | 消費 (deserialize) + 型マッピング |

両実装はこの仕様に準拠する。不整合がある場合はこのドキュメントが正とする。

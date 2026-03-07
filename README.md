# plat

Architecture as Code — eDSL, generation, verification.

ソフトウェアアーキテクチャを Haskell の値として記述し、コンパイル時の参照安全性・実行時バリデーション・複数フォーマットへの出力を得る。実装との構造的適合を tree-sitter ベースのツール (plat-verify, Rust) で検証する。

## Idea

アーキテクチャ記述言語には2つの矛盾する要求がある:

1. **構造的制約** — model に `needs` を書けてはならない、adapter に `field` があってはならない
2. **均質なデータ操作** — すべての宣言をリストで走査し、検証や生成に渡したい

plat はこれを **phantom-tagged newtype** (`Decl k`) と **消去関数** (`decl`) の2層で解決する。構築時は型レベルの制約が効き、操作時は均質な `Declaration` として扱える。

## Mental Model

アーキテクチャは5種類の宣言 (`DeclKind`) から成る:

```
Model       — データ構造の定義（field）
Boundary    — ポート/インタフェース（op）
Operation   — ユースケース（input, output, needs）
Adapter     — 実装（implements, inject）
Compose     — 配線（bind, entry）
```

これらはレイヤーに配置され、レイヤー間の依存関係が `check` で検証される。

```
Layer A ──depends──▶ Layer B

Operation(A) ──needs──▶ Boundary(B)    ← A が B に依存を許可していれば OK
Adapter(A) ──implements──▶ Boundary(B) ← 同上
```

## Quick Start

```haskell
{-# LANGUAGE OverloadedStrings #-}
import Plat.Core
import Plat.Check
import Plat.Generate.Mermaid (renderMermaid)

import qualified Data.Text.IO as TIO

-- Layers: 依存グラフを定義
core        = layer "core"
interface   = layer "interface"   `depends` [core]
application = layer "application" `depends` [core, interface]
infra       = layer "infra"       `depends` [core, application, interface]

-- Model: データ構造
order :: Decl 'Model
order = model "Order" core $ do
  field "id"     (customType "UUID")
  field "total"  decimal
  field "status" string

-- Boundary: ポート
orderRepo :: Decl 'Boundary
orderRepo = boundary "OrderRepository" interface $ do
  op "save"     ["order" .: ref order] ["err" .: error_]
  op "findById" ["id" .: customType "UUID"] ["order" .: ref order, "err" .: error_]

-- Operation: ユースケース
placeOrder :: Decl 'Operation
placeOrder = operation "PlaceOrder" application $ do
  input  "order" (ref order)
  output "err"   error_
  needs orderRepo    -- compile-time: Decl 'Boundary のみ受理

-- Adapter: 外部実装
pgRepo :: Decl 'Adapter
pgRepo = adapter "PostgresOrderRepo" infra $ do
  implements orderRepo
  inject "db" (ext "*sql.DB")

-- Architecture: 全体を組み立て
architecture :: Architecture
architecture = arch "my-service" $ do
  useLayers [core, application, interface, infra]
  registerType "UUID"
  declare order
  declare orderRepo
  declare placeOrder
  declare pgRepo

main :: IO ()
main = do
  let r = check architecture
  putStrLn $ show (length (violations r)) ++ " violations"
  TIO.putStrLn $ renderMermaid architecture
```

## Two-Layer Type Design

### Construction: `Decl k`

phantom 型パラメータ `k :: DeclKind` がコンビネータを制約する:

```haskell
needs :: Decl 'Boundary -> DeclWriter 'Operation ()
-- needs order       → compile error (Model ≠ Boundary)
-- needs pgRepo      → compile error (Adapter ≠ Boundary)

field :: Text -> TypeExpr -> DeclWriter 'Model ()
-- field inside boundary → compile error (DeclWriter 'Boundary ≠ DeclWriter 'Model)

bind :: Decl 'Boundary -> Decl 'Adapter -> DeclWriter 'Compose ()
-- bind pgRepo orderRepo → compile error (引数の型が逆)
```

### Manipulation: `Declaration`

`decl :: Decl k -> Declaration` で phantom tag を消去すると、均質なリストとして扱える:

```haskell
declares :: [Declaration] -> ArchBuilder ()  -- 異なる DeclKind を混在可能
declares [decl order, decl orderRepo, decl placeOrder]
```

検証 (`check`)・生成 (`renderMermaid`, `renderMarkdown`) はすべて `Declaration` レベルで動作する。

## Validation

`check :: Architecture -> CheckResult` はレイヤー依存・型整合性・構造制約を検証する。

| Code | What it catches |
|------|-----------------|
| V001 | レイヤー依存違反 (operation が許可されていないレイヤーの boundary を needs) |
| V002 | レイヤー循環依存 (A→B→C→A) |
| V003 | `needs` の対象が boundary でない |
| V004 | boundary に adapter 固有の要素 (inject, implements) |
| V005 | compose 外での `bind` |
| V006 | 予約語との名前衝突 |
| V007 | adapter が implements した boundary の op を充足していない |
| V008 | `bind` の左辺が boundary でない、または右辺が adapter でない |
| W001 | boundary に対応する adapter が存在しない |
| W002 | 未定義の型参照 (ext, Error, registered types は免除) |
| W003 | `@path` で指定されたファイルが存在しない (IO check) |

ルールは合成可能:

```haskell
checkWith (coreRules ++ dddRules ++ cqrsRules) architecture
```

## Extension Mechanism

拡張は **core の DeclItem を変更しない**。smart constructor + `meta` タグの薄いラッパーとして実装される。

```haskell
-- Ext.DDD の aggregate は model + meta タグ
aggregate :: Text -> LayerDef -> DeclWriter 'Model () -> Decl 'Model
aggregate name ly body = model name ly $ do
  meta "plat-ddd:kind" "aggregate"
  body
```

この設計により:
- core AST は閉じたまま (`DeclItem` に新コンストラクタを追加しない)
- 拡張ごとの検証ルールは `PlatRule` instance + `SomeRule` で合成
- meta をクエリするヘルパー (`lookupMeta`, `isAggregate` 等) で拡張固有のロジックを構築

| Module | Vocabulary | Domain |
|--------|-----------|--------|
| `Plat.Ext.DDD` | `value`, `aggregate`, `enum_`, `invariant` | Domain-Driven Design |
| `Plat.Ext.CQRS` | `command`, `query` | Command-Query Separation |
| `Plat.Ext.CleanArch` | `entity`, `port`, `impl_`, `wire` + preset layers | Clean Architecture |
| `Plat.Ext.Http` | `controller`, `route` | HTTP endpoints |
| `Plat.Ext.DBC` | `pre`, `post`, `assert_` | Design by Contract |
| `Plat.Ext.Flow` | `step`, `policy`, `guard_` | Workflow / Saga |
| `Plat.Ext.Events` | `event`, `emit`, `on_`, `apply_` | Event Sourcing |
| `Plat.Ext.Modules` | `domain`, `expose`, `import_` | Module boundaries |

## Output

### Formats

| Format | Function | Use case |
|--------|----------|----------|
| Mermaid | `renderMermaid` | ダイアグラム (needs/implements/bind の関係) |
| Markdown | `renderMarkdown` | ドキュメント生成 |

### Target Language Generation

`Plat.Target.*` は Architecture からターゲット言語のコードを生成する。3つの機能を持つ:

| Function | What it generates |
|----------|-------------------|
| `skeleton` | 型定義・インターフェース・ユースケース構造体・アダプタスタブ |
| `contract` | boundary ごとの契約テスト (adapter が op を満たすことを検証) |
| `verify` | コンパイル時適合チェック (ビルドが通る = アーキテクチャ適合) |

いずれも `Config -> Architecture -> [(FilePath, Text)]` を返す。

```haskell
import qualified Plat.Target.Go as Go

let cfg = Go.defaultConfig "github.com/example/svc"
let files = Go.skeleton cfg architecture
-- [("domain/order.go", "package domain\n..."), ...]
```

各言語の型マッピング:

| plat | Go | TypeScript | Rust |
|---------|-----|------------|------|
| `string` | `string` | `string` | `String` |
| `int` | `int` | `number` | `i64` |
| `list T` | `[]T` | `T[]` | `Vec<T>` |
| `option T` | `*T` | `T \| null` | `Option<T>` |
| `mapType K V` | `map[K]V` | `Map<K, V>` | `HashMap<K, V>` |
| `ref model` | `ModelName` | `ModelName` | `ModelName` |
| `ext "X"` | `X` (passthrough) | `X` | `X` |

`GoConfig.goTypeMap` / `goLayerPkg` 等でプロジェクト固有のマッピングを上書き可能。

## plat-verify

Architecture manifest と実装ソースコードの構造的適合性を検証するスタンドアロンツール (Rust)。

```
plat (Haskell)          plat-verify (Rust)
     │                          │
     │  manifest.json           │  source code
     ▼                          ▼
Architecture ─────────▶ Manifest ◀──────── Extracted Facts
                            │
                            ▼
                     Conformance Report
```

### チェックカテゴリ

| Category | Codes | Description |
|----------|-------|-------------|
| Existence | E0xx | 宣言に対応する型がソースに存在するか |
| Structure | S0xx | フィールド・メソッドの構造が一致するか |
| Relation | R0xx | implements/needs 関係が実装されているか |
| Drift | T0xx | manifest にない実装の検出 (opt-in) |
| Layer Deps | L0xx | レイヤー依存方向の検証 (opt-in) |

### 設定

```toml
# plat-verify.toml
[source]
language = "go"
root = "./src"
layer_match = "prefix"     # "prefix" (default) | "component" (feature-first)

[source.layer_dirs]
enterprise  = "domain"
interface   = "port"
application = "usecase"
framework   = "adapter"
```

詳細: [docs/plat-verify-spec.md](docs/plat-verify-spec.md)

## Type Expressions

`ref` は他の宣言への型参照を作る。`ext` はターゲット言語固有の型 (W002 免除)。`customType` はプロジェクト定義の型 (`registerType` で登録)。

```haskell
field "id"     (customType "UUID")     -- registerType "UUID" が必要 (W002)
field "total"  decimal                 -- ビルトイン
field "items"  (list (ref orderItem))  -- 他の宣言への参照
inject "db"    (ext "*sql.DB")         -- 外部型 (W002 免除)
field "err"    error_                  -- 予約型 (W002 免除)
```

## Examples

4つのアーキテクチャパターンを plat で記述:

| Example | Pattern | Language | Extensions |
|---------|---------|----------|------------|
| `GoCleanArch` | Clean Architecture | Go | CleanArch, DDD |
| `GoFeatureSliced` | Feature-Sliced CA | Go | CleanArch, DDD, Modules |
| `TsHexagonal` | Hexagonal | TypeScript | DDD |
| `RustCqrsEs` | CQRS + Event Sourcing | Rust | CQRS, Events, DDD, Flow |

各 example はアーキテクチャ定義を `Arch/` モジュール階層で構造化し、`cabal run` で `dist/` に成果物を出力する:

```
examples/go-clean-arch/
  GoCleanArch.hs          -- Main: assembly + output
  Arch/
    Shared.hs             -- 共有 model (Money, Address)
    Order.hs              -- Order ドメイン
    Customer.hs           -- Customer ドメイン
    Catalog.hs            -- Catalog ドメイン
    Payment.hs            -- Payment ドメイン
  dist/                   -- 生成物 (gitignore)
    check.txt
    architecture.md
    architecture.mmd
    manifest.toml         -- JSON manifest
    skeleton/             -- Go スケルトンコード
    verify/               -- コンパイル時適合チェック
```

各 `Arch/*.hs` は `declareAll :: ArchBuilder ()` をエクスポートし、Main が組み立てる:

```haskell
architecture = arch "order-service" $ do
  useLayers cleanArchLayers
  registerType "UUID"
  Arch.Shared.declareAll
  Arch.Order.declareAll
  Arch.Customer.declareAll
  ...
```

実行:

```
cabal run example-go-clean-arch     # → dist/ にファイル出力
cabal run example-ts-hexagonal
cabal run example-rust-cqrs-es
cabal run example-go-feature-sliced
```

## Development

```
mise run build            # Build
mise run test             # 97 tests
mise run lint             # -Werror
mise run examples         # Run all examples
mise run repl             # GHCi
mise run watch            # Rebuild on change (requires entr)
mise run verify:build     # Build plat-verify (Rust)
mise run verify:test      # Test plat-verify (Rust)
```

Requires GHC >= 9.10 (GHC2024, recommended 9.12+). `OverloadedStrings` のみ必須。plat-verify (Rust) は Cargo で別途ビルド。

## Documentation

- [docs/architecture.md](docs/architecture.md) — モジュール構成、AST 設計、モナド設計
- [docs/validation-rules.md](docs/validation-rules.md) — 全ルールの詳細仕様
- [docs/extensions.md](docs/extensions.md) — 拡張パターンと meta タグ一覧
- [docs/plat-verify-spec.md](docs/plat-verify-spec.md) — plat-verify 仕様
- [docs/roadmap.md](docs/roadmap.md) — 開発ロードマップと今後の方向性
- [docs/spec-v0.6.md](docs/spec-v0.6.md) — 正式仕様 (current)

# plat

Architecture as Code — eDSL, generation, verification.

ソフトウェアアーキテクチャを Haskell の値として記述し、コンパイル時の参照安全性・実行時バリデーション・複数フォーマットへの出力を得る。実装との構造的適合を tree-sitter ベースのツール (Rust) で検証する。

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
import Plat.Generate.Plat (render)

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

検証 (`check`)・生成 (`render`) はすべて `Declaration` レベルで動作する。

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
| `.plat` | `render`, `renderFiles` | Plat ツールチェーンとの統合 |
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

| Example | Architecture | Extensions |
|---------|-------------|------------|
| `GoCleanArch` | Clean Architecture (enterprise/application/interface/framework) | CleanArch, DDD, Http |
| `TsHexagonal` | Hexagonal (domain/port/adapter) | Core only |
| `RustCqrsEs` | CQRS + Event Sourcing | CQRS, Events, DDD, Flow |

```
cabal run example-go-clean-arch
cabal run example-ts-hexagonal
cabal run example-rust-cqrs-es
```

## Development

```
mise run build      # Build
mise run test       # 114 tests
mise run lint       # -Werror
mise run examples   # Run all examples
mise run repl       # GHCi
mise run watch      # Rebuild on change (requires entr)
```

Requires GHC >= 9.6 (recommended 9.10+). `OverloadedStrings` のみ必須。

## Documentation

- [docs/architecture.md](docs/architecture.md) — モジュール構成、AST 設計、モナド設計
- [docs/validation-rules.md](docs/validation-rules.md) — 全ルールの詳細仕様
- [docs/extensions.md](docs/extensions.md) — 拡張パターンと meta タグ一覧
- [docs/roadmap.md](docs/roadmap.md) — 開発ロードマップと今後の方向性
- [docs/plat-verify-spec.md](docs/plat-verify-spec.md) — plat-verify 仕様
- [docs/spec-v0.6.md](docs/spec-v0.6.md) — 正式仕様 (current)
- [docs/spec-v0.5.md](docs/spec-v0.5.md) — previous

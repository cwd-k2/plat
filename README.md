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
Layer A ──depends──> Layer B

Operation(A) ──needs──> Boundary(B)    <- A が B に依存を許可していれば OK
Adapter(A) ──implements──> Boundary(B) <- 同上
```

## Getting Started

### 前提条件

- **GHC >= 9.10** + **cabal >= 3.0** — [ghcup](https://www.haskell.org/ghcup/) でインストール
- **Rust stable** — [rustup](https://rustup.rs/) (plat-verify を使う場合)

### ワークフロー

```
1. アーキテクチャを Haskell で記述
2. cabal run で成果物を生成
3. plat-verify で実装コードとの適合性を検証
```

### Step 1: プロジェクトセットアップ

plat を cabal の依存に追加する:

```cabal
-- my-service-arch.cabal
cabal-version: 3.0
name:    my-service-arch
version: 0.1.0

executable my-service-arch
  main-is: Main.hs
  hs-source-dirs: arch
  build-depends:
    , base       >= 4.20 && < 5
    , plat
    , text       >= 2.0
    , directory  >= 1.3
    , filepath   >= 1.4
  default-language: GHC2024
  default-extensions: OverloadedStrings
```

### Step 2: アーキテクチャを記述

```haskell
-- arch/Main.hs
module Main where

import Plat.Core
import Plat.Check
import Plat.Generate.Mermaid   (renderMermaid)
import Plat.Generate.Markdown  (renderMarkdown)
import Plat.Verify.Manifest    (manifest, renderManifest)

import Data.Text (Text)
import qualified Data.Text.IO as TIO
import System.Directory (createDirectoryIfMissing)

-- Layers
dom   = layer "domain"
port_ = layer "port"           `depends` [dom]
app   = layer "application"    `depends` [dom, port_]
infra = layer "infrastructure" `depends` [dom, port_, app]

-- Model
order :: Decl 'Model
order = model "Order" dom $ do
  field "id"     (customType "UUID")
  field "total"  decimal
  field "status" string

-- Boundary (port)
orderRepo :: Decl 'Boundary
orderRepo = boundary "OrderRepository" port_ $ do
  op "save"     ["order" .: ref order] ["err" .: error_]
  op "findById" ["id" .: customType "UUID"] ["order" .: ref order, "err" .: error_]

-- Operation (use case)
placeOrder :: Decl 'Operation
placeOrder = operation "PlaceOrder" app $ do
  input  "order" (ref order)
  output "err"   error_
  needs orderRepo

-- Adapter
pgRepo :: Decl 'Adapter
pgRepo = adapter "PostgresOrderRepo" infra $ do
  implements orderRepo
  inject "db" (ext "*sql.DB")

-- Wiring
wiring :: Decl 'Compose
wiring = compose "ServiceWiring" $ do
  bind orderRepo pgRepo
  entry placeOrder

-- Architecture
architecture :: Architecture
architecture = arch "my-service" $ do
  useLayers [dom, port_, app, infra]
  registerType "UUID"
  declare order
  declare orderRepo
  declare placeOrder
  declare pgRepo
  declare wiring

out :: FilePath -> Text -> IO ()
out fp content = createDirectoryIfMissing True "dist" >> TIO.writeFile fp content

main :: IO ()
main = do
  out "dist/check.txt"         (prettyCheck (check architecture))
  out "dist/manifest.json"     (renderManifest (manifest architecture))
  out "dist/architecture.md"   (renderMarkdown architecture)
  out "dist/architecture.mmd"  (renderMermaid architecture)
  putStrLn "Generated: dist/{check.txt, manifest.json, architecture.md, architecture.mmd}"
```

### Step 3: 生成

```bash
cabal run my-service-arch
```

### Step 4: plat-verify で実装を検証

```bash
plat-verify dist/manifest.json --language go --root ./src
```

詳細: [docs/plat-verify-spec.md](docs/plat-verify-spec.md)

## API Overview

```haskell
import Plat.Core
import Plat.Check

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
```

## Two-Layer Type Design

### Construction: `Decl k`

phantom 型パラメータ `k :: DeclKind` がコンビネータを制約する:

```haskell
needs :: Decl 'Boundary -> DeclWriter 'Operation ()
-- needs order       -> compile error (Model /= Boundary)

field :: Text -> TypeExpr -> DeclWriter 'Model ()
-- field inside boundary -> compile error

bind :: Decl 'Boundary -> Decl 'Adapter -> DeclWriter 'Compose ()
-- bind pgRepo orderRepo -> compile error (引数の型が逆)
```

### Manipulation: `Declaration`

`decl :: Decl k -> Declaration` で phantom tag を消去すると、均質なリストとして扱える:

```haskell
declares :: [Declaration] -> ArchBuilder ()
declares [decl order, decl orderRepo, decl placeOrder]
```

## Validation

`check :: Architecture -> CheckResult` はレイヤー依存・型整合性・構造制約を検証する。

| Code | What it catches |
|------|-----------------|
| V001 | レイヤー依存違反 |
| V002 | レイヤー循環依存 |
| V003 | `needs` の対象が boundary でない |
| V004 | boundary に adapter 固有の要素 |
| V005 | compose 外での `bind` |
| V006 | 予約語との名前衝突 |
| V007 | adapter が boundary の op を充足していない |
| V008 | `bind` の型不一致 |
| V009 | 同名宣言の重複 |
| W001 | boundary に adapter がない |
| W002 | 未定義の型参照 (ext, Error, registered types は免除) |
| W003 | 多重 implements |
| W004 | @path ファイル不在 (IO) |

ルールは合成可能:

```haskell
checkWith (coreRules ++ dddRules ++ cqrsRules) architecture
```

## Extension Mechanism

拡張は **core の DeclItem を変更しない**。smart constructor + `meta` タグの薄いラッパーとして実装される。

| Module | Vocabulary | Domain |
|--------|-----------|--------|
| `Plat.Ext.DDD` | `value`, `aggregate`, `enum`, `invariant` | Domain-Driven Design |
| `Plat.Ext.CQRS` | `command`, `query` | Command-Query Separation |
| `Plat.Ext.CleanArch` | `entity`, `port`, `impl`, `wire` + preset layers | Clean Architecture |
| `Plat.Ext.Http` | `controller`, `route` | HTTP endpoints |
| `Plat.Ext.DBC` | `pre`, `post`, `assert_` | Design by Contract |
| `Plat.Ext.Flow` | `step`, `policy`, `guard_` | Workflow / Saga |
| `Plat.Ext.Events` | `event`, `emit`, `on_`, `apply` | Event Sourcing |
| `Plat.Ext.Modules` | `domain`, `expose`, `import_` | Module boundaries |

## Output

| Format | Function | Use case |
|--------|----------|----------|
| Mermaid | `renderMermaid` | ダイアグラム |
| Markdown | `renderMarkdown` | ドキュメント生成 |
| JSON manifest | `renderManifest` | Rust ツール群への入力 |

## plat-verify

manifest と実装ソースの構造的適合性を検証するスタンドアロンツール (Rust)。

| Category | Codes | Description |
|----------|-------|-------------|
| Existence | E0xx | 宣言に対応する型がソースに存在するか |
| Structure | S0xx | フィールド・メソッドの構造が一致するか |
| Relation | R0xx | implements/needs 関係が実装されているか |
| Drift | T0xx | manifest にない実装の検出 (opt-in) |
| Layer Deps | L0xx | レイヤー依存方向の検証 (opt-in) |

詳細: [docs/plat-verify-spec.md](docs/plat-verify-spec.md)

## Type Expressions

```haskell
field "id"     (customType "UUID")     -- registerType "UUID" が必要
field "total"  decimal                 -- ビルトイン
field "items"  (list (ref orderItem))  -- 他の宣言への参照
field "items"  (listOf orderItem)      -- 参照コンビネータ (shorthand)
inject "db"    (ext "*sql.DB")         -- 外部型 (TExt, W002 免除)
field "err"    error_                  -- 予約型
```

## Development

```
mise run build            # Build
mise run test             # 226 tests
mise run lint             # -Werror
mise run repl             # GHCi
mise run watch            # Rebuild on change
mise run verify:build     # Build plat-verify (Rust)
mise run verify:test      # Test plat-verify (Rust)
```

Requires GHC >= 9.10 (GHC2024, recommended 9.12+). `OverloadedStrings` のみ必須。

## Documentation

- [docs/spec/](docs/spec/) — 正式仕様 (体系的に分割)
- [docs/architecture.md](docs/architecture.md) — モジュール構成、AST 設計、モナド設計
- [docs/validation-rules.md](docs/validation-rules.md) — 全ルールの詳細仕様
- [docs/extensions.md](docs/extensions.md) — 拡張パターンと meta タグ一覧
- [docs/plat-verify-spec.md](docs/plat-verify-spec.md) — plat-verify 仕様
- [docs/tooling-direction.md](docs/tooling-direction.md) — Haskell/Rust 責務分離
- [docs/roadmap.md](docs/roadmap.md) — 開発ロードマップ

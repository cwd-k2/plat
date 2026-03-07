# plat

Architecture as Code — define, verify, generate.

manifest.json を軸に、アーキテクチャの定義・実装の検証・コード生成を行うツールチェーン。

```
                      ┌─────────────────────────────────────────────────────┐
                      │                  manifest.json                      │
                      └────────┬────────┬────────┬────────┬────────┬───────┘
                               │        │        │        │        │
  Haskell eDSL ───generate───▶ │        │        │        │        │
  Source code ────--init─────▶ │        │        │        │        │
  Hand-written ──────────────▶ │        │        │        │        │
                               ▼        ▼        ▼        ▼        ▼
                            verify   skeleton contract  deprules   doc
```

## Quick Start

### A. 既存コードベースから始める（推奨）

ソースコードを解析して manifest を自動生成し、すぐに検証を開始できる。

```bash
# 1. ビルド
cargo build --release

# 2. ソースから manifest を逆生成
plat-verify --init --name my-service --root ./src --language go > manifest.json

# 3. 設定ファイルを作成
cat > plat-verify.toml << 'EOF'
[source]
language = "go"
root = "./src"

[source.layer_dirs]
domain    = "domain"
interface = "port"
application = "usecase"
infra     = "infra"
EOF

# 4. 検証
plat-verify manifest.json

# 5. manifest を手で洗練し、再検証を繰り返す
```

`--init` はソースから boundary / adapter / operation / model を推論する。生成された manifest を出発点として手動で洗練していく（Reflexion Model）。

### B. Haskell eDSL でゼロから定義する

型安全な eDSL でアーキテクチャを記述し、manifest を生成する。

```bash
# 前提: GHC >= 9.10, cabal >= 3.0
cabal build
cabal run my-service-arch
# → dist/manifest.json が生成される
```

```haskell
module Main where

import Plat.Core
import Plat.Check
import Plat.Verify.Manifest (manifest, renderManifest)
import qualified Data.Text.IO as TIO

-- レイヤー定義
dom   = layer "domain"
port_ = layer "port"        `depends` [dom]
app   = layer "application" `depends` [dom, port_]
infra = layer "infra"       `depends` [dom, port_, app]

-- Model: データ構造
order :: Decl 'Model
order = model "Order" dom $ do
  field "id"     (customType "UUID")
  field "total"  decimal
  field "status" string

-- Boundary: ポート（インターフェース）
orderRepo :: Decl 'Boundary
orderRepo = boundary "OrderRepository" port_ $ do
  op "save"     ["order" .: ref order] ["err" .: error_]
  op "findById" ["id" .: customType "UUID"] ["order" .: ref order, "err" .: error_]

-- Operation: ユースケース
placeOrder :: Decl 'Operation
placeOrder = operation "PlaceOrder" app $ do
  input  "order" (ref order)
  output "err"   error_
  needs orderRepo

-- Adapter: 実装
pgRepo :: Decl 'Adapter
pgRepo = adapter "PostgresOrderRepo" infra $ do
  implements orderRepo
  inject "db" (ext "*sql.DB")

-- Architecture: 全体を組み立て
architecture :: Architecture
architecture = arch "my-service" $ do
  useLayers [dom, port_, app, infra]
  registerType "UUID"
  declare order
  declare orderRepo
  declare placeOrder
  declare pgRepo

main :: IO ()
main = TIO.writeFile "dist/manifest.json" (renderManifest (manifest architecture))
```

eDSL は phantom type (`Decl k`) でコンパイル時に不正な組み合わせを検出する:

```haskell
needs orderRepo     -- OK: Decl 'Boundary
needs order         -- compile error: Model /= Boundary
field "x" int       -- OK in Model
field "x" int       -- compile error in Boundary
```

---

## ツール一覧

manifest.json を入力として動作する Rust 製のスタンドアロンツール群。

### plat-verify — 構造適合性検証

manifest とソースコードを照合し、アーキテクチャの実装適合性を検証する。

```bash
# 基本
plat-verify manifest.json --language go --root ./src

# 設定ファイル使用
plat-verify manifest.json -c plat-verify.toml

# CI 向け: JSON 出力 + error のみ
plat-verify manifest.json --format json --severity error

# 特定のチェックカテゴリのみ
plat-verify manifest.json --check existence --check structure

# ファイル監視モード
plat-verify manifest.json --watch

# LSP サーバーモード
plat-verify manifest.json --lsp
```

**チェックカテゴリ:**

| Category | Codes | 内容 | Default |
|----------|-------|------|---------|
| existence | E001-E004 | 宣言に対応する型がソースに存在するか | on |
| structure | S001-S006 | フィールド・メソッドの構造が一致するか | on |
| relation | R001-R004 | implements/needs/bindings が実装されているか | on |
| drift | T001-T004 | manifest にない型・フィールド・メソッドの検出 | off |
| layer-deps | L001 | レイヤー依存方向の違反検出 | off |
| imports | I001-I002 | import/use 文のレイヤー越え・循環検出 | off |
| naming | N001-N003 | 命名規約違反の検出 | off |

**出力例:**

```
plat-verify: order-service (go)

[E002] boundary OrderRepository not found
       expected: interface in port/
[S001] model Order: missing field "shipping"
       expected: Address (in domain/order.go)
[R001] adapter PostgresOrderRepo does not implement OrderRepository
       missing methods: findAll, delete
       source: infra/postgres_order_repo.go:12

── Summary ────────────────────────────────────────
  2 error(s), 1 warning(s), 0 info
  declarations: 15 checked, 13 ok, 2 issues
  convergence:  types 13/15, fields 27/28, methods 6/8
  health score: 90%
```

**追加モード:**

```bash
# --suggest: drift findings から manifest パッチを提案
plat-verify manifest.json --suggest

# --contracts: 2つの manifest 間の互換性を検証
plat-verify consumer.json --contracts provider.json

# --init: ソースコードから manifest を逆生成
plat-verify --init --name my-service --root ./src --language go
```

### plat-doc — ドキュメント生成

manifest から Markdown ドキュメント、Mermaid 図、DSM (Dependency Structure Matrix) を生成する。

```bash
# Markdown ドキュメント
plat-doc manifest.json --format markdown > architecture.md

# Mermaid ダイアグラム
plat-doc manifest.json --format mermaid > architecture.mmd

# DSM (依存構造マトリクス)
plat-doc manifest.json --format dsm
```

### plat-skeleton — コードスカフォールド生成

manifest から型定義・インターフェース・構造体のスケルトンコードを生成する。

```bash
plat-skeleton manifest.json --language go --output ./src \
  --layer-dir domain=domain \
  --layer-dir interface=port \
  --layer-dir application=usecase \
  --layer-dir framework=infra \
  --module example.com/myservice
```

### plat-contract — テストスケルトン生成

boundary の ops からインターフェーステストのスケルトンを生成する。

```bash
plat-contract manifest.json --language go --output ./test \
  --layer-dir interface=port
```

### plat-deprules — linter 依存ルール生成

レイヤー依存定義から linter の設定ファイルを生成する。

```bash
# 依存マトリクス表示
plat-deprules manifest.json --format matrix

# Go depguard 設定
plat-deprules manifest.json --format depguard \
  --module example.com/myservice \
  --layer-dir domain=domain \
  --layer-dir interface=port

# ESLint import ルール
plat-deprules manifest.json --format eslint \
  --layer-dir domain=src/domain \
  --layer-dir interface=src/port
```

---

## 設定ファイル

`plat-verify.toml` で plat-verify の挙動をカスタマイズする。

```toml
[source]
language = "go"          # go | typescript | rust
root = "./src"           # ソースルート
layer_match = "prefix"   # prefix | component

[source.layer_dirs]      # レイヤー → ディレクトリ
domain      = "domain"
interface   = "port"
application = "usecase"
infra       = "infra"

[types]                  # manifest 型 → ソース型の追加マッピング
UUID = "uuid.UUID"
Money = "domain.Money"

[naming]
type_case   = "PascalCase"   # 型名の命名規約
field_case  = "camelCase"    # フィールド名 (Go: PascalCase, TS: camelCase, Rust: snake_case)
method_case = "PascalCase"   # メソッド名 (同上)

[checks]
existence  = true
structure  = true
relation   = true
drift      = false           # opt-in
layer_deps = false           # opt-in
imports    = false           # opt-in
naming     = false           # opt-in

[checks.severity]            # 個別チェックの severity 変更
S002 = "warning"
```

### layer_match

| Mode | 対象の構成 | 例 |
|------|-----------|-----|
| `prefix` | レイヤーファースト | `domain/order.go`, `port/repo.go` |
| `component` | フィーチャーファースト | `order/domain/model.go`, `order/port/repo.go` |

### 言語別デフォルト型マッピング

| Manifest | Go | TypeScript | Rust |
|----------|-----|-----------|------|
| `String` | `string` | `string` | `String` |
| `Int` | `int` | `number` | `i64` |
| `Bool` | `bool` | `boolean` | `bool` |
| `List<T>` | `[]T` | `T[]` | `Vec<T>` |
| `Map<K,V>` | `map[K]V` | `Map<K,V>` | `HashMap<K,V>` |
| `DateTime` | `time.Time` | `Date` | `DateTime<Utc>` |
| `Error` | `error` | `Error` | `Result<T, String>` |

全マッピングは [docs/plat-verify-spec.md](docs/plat-verify-spec.md) を参照。

---

## manifest.json フォーマット

5 種類の宣言 (`kind`) でアーキテクチャを記述する:

| Kind | 用途 | 主要フィールド |
|------|------|---------------|
| `model` | データ構造 | `fields` |
| `boundary` | ポート / インターフェース | `ops` |
| `operation` | ユースケース | `inputs`, `outputs`, `needs` |
| `adapter` | 外部実装 | `implements`, `injects` |
| `compose` | 配線 | `entries` |

これらは `layers` に配置され、レイヤー間の依存方向が制約される。

```jsonc
{
  "schema_version": "0.6",
  "name": "my-service",
  "layers": [
    { "name": "domain", "depends": [] },
    { "name": "port",   "depends": ["domain"] },
    { "name": "app",    "depends": ["domain", "port"] },
    { "name": "infra",  "depends": ["domain", "port", "app"] }
  ],
  "declarations": [
    {
      "name": "Order",
      "kind": "model",
      "layer": "domain",
      "fields": [
        { "name": "ID", "type": "String" },
        { "name": "Total", "type": "Decimal" }
      ]
    },
    {
      "name": "OrderRepository",
      "kind": "boundary",
      "layer": "port",
      "ops": [
        {
          "name": "Save",
          "inputs": [{ "name": "order", "type": "Order" }],
          "outputs": [{ "name": "", "type": "Error" }]
        }
      ]
    },
    {
      "name": "PlaceOrder",
      "kind": "operation",
      "layer": "app",
      "needs": ["OrderRepository"],
      "inputs": [{ "name": "order", "type": "Order" }],
      "outputs": [{ "name": "err", "type": "Error" }]
    },
    {
      "name": "PostgresOrderRepo",
      "kind": "adapter",
      "layer": "infra",
      "implements": "OrderRepository",
      "injects": [{ "name": "db", "type": "ext:*sql.DB" }]
    }
  ],
  "bindings": [
    { "boundary": "OrderRepository", "adapter": "PostgresOrderRepo" }
  ]
}
```

完全な仕様: [docs/spec/manifest.md](docs/spec/manifest.md)

---

## CI 統合

```yaml
# GitHub Actions
steps:
  - uses: actions/checkout@v4

  # Haskell eDSL から manifest を生成する場合
  - name: Generate manifest
    run: cabal run my-arch

  # 検証
  - name: Verify architecture conformance
    run: plat-verify manifest.json -c plat-verify.toml --format json --severity error

  # Exit code: 0 = pass, 1 = error found, 2 = input error
```

`--format lsp` で LSP Diagnostic 形式の JSON を出力でき、エディタ統合やカスタムレポートに利用できる。

### VS Code 拡張

`editors/vscode/` に LSP クライアント拡張がある。manifest ファイルを自動検出し、保存時に検証結果をエディタに表示する。

---

## Examples

| Example | 言語 | 構成 | 特徴 |
|---------|------|------|------|
| [`go-clean-arch`](examples/go-clean-arch/) | Go | Clean Architecture | 5 ドメイン, 拡張 (DDD, CleanArch, Http) |
| [`go-feature-sliced`](examples/go-feature-sliced/) | Go | Feature-Sliced | `layer_match = "component"` |
| [`ts-hexagonal`](examples/ts-hexagonal/) | TypeScript | Hexagonal | TS class + interface |
| [`rust-cqrs-es`](examples/rust-cqrs-es/) | Rust | CQRS + Event Sourcing | trait + impl |
| [`cross-language`](examples/cross-language/) | Go + TS | マルチサービス | `--contracts` でサービス間検証 |
| [`poc-roundtrip`](examples/poc-roundtrip/) | Go | ラウンドトリップ | `--init` → 手動洗練 → verify |

---

## Haskell eDSL リファレンス

### 拡張モジュール

core の `DeclItem` を変更せず、smart constructor + `meta` タグで語彙を拡張する:

| Module | 語彙 | ドメイン |
|--------|------|---------|
| `Plat.Ext.DDD` | `value`, `aggregate`, `enum`, `invariant` | Domain-Driven Design |
| `Plat.Ext.CQRS` | `command`, `query` | Command-Query Separation |
| `Plat.Ext.CleanArch` | `entity`, `port`, `impl`, `wire` + preset layers | Clean Architecture |
| `Plat.Ext.Http` | `controller`, `route` | HTTP endpoints |
| `Plat.Ext.DBC` | `pre`, `post`, `assert_` | Design by Contract |
| `Plat.Ext.Flow` | `step`, `policy`, `guard_` | Workflow / Saga |
| `Plat.Ext.Events` | `event`, `emit`, `on_`, `apply` | Event Sourcing |
| `Plat.Ext.Modules` | `domain`, `expose`, `import_` | Module boundaries |

### 検証ルール

`check :: Architecture -> CheckResult` で検証を実行。ルールは合成可能:

```haskell
checkWith (coreRules ++ dddRules ++ cqrsRules) architecture
```

| Code | 内容 |
|------|------|
| V001 | レイヤー依存違反 |
| V002 | レイヤー循環依存 |
| V003 | `needs` の対象が boundary でない |
| V004 | boundary に adapter 固有の要素 |
| V005 | compose 外での `bind` |
| V006 | 予約語との名前衝突 |
| V007 | adapter が boundary の op を充足していない |
| V008 | `bind` の型不一致 |
| V009 | 同名宣言の重複 |
| V010 | relation の参照先が存在しない |
| W001 | boundary に adapter がない |
| W002 | 未定義の型参照 |
| W003 | 多重 implements |
| W004 | @path ファイル不在 |

---

## ビルド

```bash
# Rust ツール群
cargo build                     # 全ツールビルド
cargo test                      # 全テスト (172 tests)

# Haskell eDSL
cabal build                     # ライブラリビルド
cabal test                      # 全テスト (240 tests)

# mise タスク (利用可能な場合)
mise run build
mise run test
```

**前提条件:**
- Rust stable ([rustup](https://rustup.rs/))
- GHC >= 9.10 + cabal >= 3.0 ([ghcup](https://www.haskell.org/ghcup/)) — Haskell eDSL を使う場合

---

## ドキュメント

### 仕様

- [docs/spec/manifest.md](docs/spec/manifest.md) — manifest JSON フォーマット仕様
- [docs/spec/](docs/spec/) — AST, 型システム, 検証, 制約, 代数, 関係, 拡張

### ツール

- [docs/plat-verify-spec.md](docs/plat-verify-spec.md) — plat-verify 仕様 (チェックコード, 型マッピング, tree-sitter 抽出)
- [docs/tooling-direction.md](docs/tooling-direction.md) — Haskell/Rust 責務分離の設計方針

### 設計

- [docs/architecture.md](docs/architecture.md) — モジュール構成, AST 設計, モナド設計
- [docs/validation-rules.md](docs/validation-rules.md) — 全検証ルールの詳細仕様
- [docs/extensions.md](docs/extensions.md) — 拡張の設計パターンと meta タグ一覧

### 形式仕様

- [docs/formal/](docs/formal/) — BNF 構文, 検証述語, 代数的性質

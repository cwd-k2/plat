# plat-verify Specification

Architecture manifest と実装ソースコードの構造的適合性を検証するスタンドアロンツール。

## 1. Overview

plat-verify は以下のパイプラインで動作する:

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

plat が Architecture から言語非依存の JSON manifest を生成し、plat-verify がソースコードから構造的事実を抽出して manifest と照合する。manifest が両者の interface boundary となる。

### Goals

- **構造適合**: 実装がアーキテクチャ宣言と一致しているかを検証する
- **言語横断**: Go, TypeScript, Rust を単一のツールでカバーする
- **CI 統合**: 非ゼロ終了コード + 機械可読出力で CI パイプラインに組み込める
- **漸進的採用**: 全チェックを一度に強制せず、カテゴリ単位で有効化/無効化できる

### Non-Goals

- ビルド/コンパイルの代替 (コンパイル時型チェックは `Target.*.verify` の責務)
- import 制限の強制 (既存 linter + `DepRules` 設定生成の責務)
- テスト実行 (contract test は `Target.*.contract` の責務)

## 2. Manifest Format

`Plat.Verify.Manifest` が生成する JSON。plat-verify の入力。

```jsonc
{
  "name": "order-service",
  "layers": [
    { "name": "enterprise", "depends": [] },
    { "name": "interface", "depends": ["enterprise"] },
    { "name": "application", "depends": ["enterprise", "interface"] },
    { "name": "framework", "depends": ["enterprise", "interface", "application"] }
  ],
  "declarations": [
    {
      "name": "Order",
      "kind": "model",           // "model" | "boundary" | "operation" | "adapter" | "compose"
      "layer": "enterprise",     // nullable: compose has no layer
      "fields": [                // model fields
        { "name": "id", "type": "UUID" },
        { "name": "total", "type": "Money" }
      ],
      "ops": [                   // boundary operations
        {
          "name": "save",
          "inputs":  [{ "name": "order", "type": "Order" }],
          "outputs": [{ "name": "err", "type": "Error" }]
        }
      ],
      "needs": ["OrderRepository", "PaymentGateway"],  // operation dependencies
      "implements": "OrderRepository",                  // adapter target (nullable)
      "injects": [{ "name": "db", "type": "*sql.DB" }], // adapter dependencies
      "entries": ["OrderController"]                     // compose entry points
    }
  ],
  "bindings": [
    { "boundary": "OrderRepository", "adapter": "PostgresOrderRepo" }
  ]
}
```

### 型の表記

manifest 内の型は言語非依存の正規形で記述される。

| Manifest type | 意味 |
|---------------|------|
| `String`, `Int`, `Float`, `Decimal`, `Bool` | ビルトインプリミティブ |
| `Unit`, `Bytes`, `DateTime`, `Any` | ビルトイン特殊型 |
| `List<T>` | リスト型 |
| `Map<K, V>` | マップ型 |
| `Option<T>` | nullable / optional |
| `Set<T>` | 集合型 |
| `Result<T, E>` | 結果型 |
| `Stream<T>` | ストリーム型 |
| `T?` | nullable (Option<T> の短縮) |
| `Money`, `Order` | ユーザー定義型 (TRef) |
| `Error` | エラー型 (言語ごとに特殊扱い) |

## 3. Configuration

plat-verify は設定ファイル `plat-verify.toml` で動作をカスタマイズする。

```toml
# plat-verify.toml

[source]
language = "go"                    # "go" | "typescript" | "rust"
root = "./src"                     # ソースルートディレクトリ

[source.layer_dirs]                # layer → ディレクトリのマッピング
enterprise  = "domain"
interface   = "port"
application = "usecase"
framework   = "infra"

[types]                            # manifest 型 → ソース型の追加マッピング
UUID = "uuid.UUID"
Money = "domain.Money"

[naming]
# 型名の変換規則 (default: identity — manifest 名をそのまま使用)
type_case = "PascalCase"           # "PascalCase" (default)
# フィールド/メソッド名の変換規則
field_case = "camelCase"           # Go/TS default: "camelCase", Rust: "snake_case"
method_case = "PascalCase"         # Go default: "PascalCase", TS: "camelCase", Rust: "snake_case"

[checks]
# カテゴリ単位で有効/無効を制御
existence = true                   # E0xx: 宣言の存在チェック
structure = true                   # S0xx: フィールド/メソッド構造チェック
relation  = true                   # R0xx: implements/needs 関係チェック
drift     = false                  # T0xx: manifest にない実装の検出 (opt-in)

[checks.severity]
# 個別チェックの severity override
S002 = "warning"                   # フィールド型不一致を warning に下げる例
```

### Language Defaults

言語を指定すると以下のデフォルトが適用される。明示的な設定で上書き可能。

| Setting | Go | TypeScript | Rust |
|---------|-----|-----------|------|
| `field_case` | `PascalCase` | `camelCase` | `snake_case` |
| `method_case` | `PascalCase` | `camelCase` | `snake_case` |
| `Error` mapping | `error` (return value) | `Error` (throw) | `Result<T, String>` |
| File extension | `.go` | `.ts` | `.rs` |

### Type Mapping Defaults

| Manifest | Go | TypeScript | Rust |
|----------|-----|-----------|------|
| `String` | `string` | `string` | `String` |
| `Int` | `int` | `number` | `i64` |
| `Float` | `float64` | `number` | `f64` |
| `Decimal` | `float64` | `number` | `f64` |
| `Bool` | `bool` | `boolean` | `bool` |
| `Unit` | `struct{}` | `void` | `()` |
| `Bytes` | `[]byte` | `Uint8Array` | `Vec<u8>` |
| `DateTime` | `time.Time` | `Date` | `DateTime<Utc>` |
| `List<T>` | `[]T` | `T[]` | `Vec<T>` |
| `Map<K,V>` | `map[K]V` | `Map<K,V>` | `HashMap<K,V>` |
| `Option<T>` | `*T` | `T \| null` | `Option<T>` |
| `Set<T>` | `map[T]struct{}` | `Set<T>` | `HashSet<T>` |

## 4. Source Fact Model

plat-verify がソースコードから抽出する構造的事実の型。

```
SourceFact
  ├── TypeDef          -- struct / interface / class / trait / enum
  │     name: String
  │     kind: Struct | Interface | Trait | Class | Enum
  │     file: FilePath
  │     fields: [(name, type_str)]
  │     methods: [MethodDef]
  │     implements: [String]      -- Go: 暗黙 (signature matching), TS: explicit, Rust: explicit
  │
  ├── MethodDef
  │     name: String
  │     params: [(name, type_str)]
  │     returns: [type_str]
  │
  ├── ImportDef         -- import / use 文
  │     source_file: FilePath
  │     target: String            -- package path / module path
  │
  └── FileDef
        path: FilePath
        layer: Option<String>     -- layer_dirs から逆引き
        types: [TypeDef]
        imports: [ImportDef]
```

### tree-sitter 抽出対象

| Fact | Go | TypeScript | Rust |
|------|-----|-----------|------|
| Struct fields | `type_declaration` > `struct_type` > `field_declaration_list` | `class_declaration` > `class_body` > `public_field_definition` | `struct_item` > `field_declaration_list` |
| Interface methods | `type_declaration` > `interface_type` > `method_elem` (v0.23+) / `method_spec` | `interface_declaration` > `object_type` > `method_signature` | `trait_item` > `declaration_list` > `function_signature_item` |
| Implements | Method receiver + signature matching (暗黙) | `class_heritage` > `implements_clause` | `impl_item` with trait path |
| Imports | `import_declaration` | `import_statement` | `use_declaration` |

## 5. Conformance Checks

manifest の各宣言に対して、ソースコードの事実を照合する。

### E0xx: Existence (存在チェック)

| Code | Severity | Condition |
|------|----------|-----------|
| E001 | error | `model` 宣言に対応する struct/type が見つからない |
| E002 | error | `boundary` 宣言に対応する interface/trait が見つからない |
| E003 | error | `adapter` 宣言に対応する struct/class が見つからない |
| E004 | warning | `operation` 宣言に対応する struct/type/function が見つからない |

検索ロジック:

1. 宣言の `layer` から `layer_dirs` でディレクトリを特定
2. そのディレクトリ配下のソースファイルを tree-sitter でパース
3. `naming.type_case` に従って名前を変換し、一致する型定義を探索

### S0xx: Structure (構造チェック)

| Code | Severity | Condition |
|------|----------|-----------|
| S001 | warning | model のフィールドがソース struct に存在しない |
| S002 | info | model のフィールド型が一致しない (型マッピング適用後) |
| S003 | error | boundary の op がソース interface/trait に存在しない |
| S004 | warning | boundary の op のパラメータ数が一致しない |
| S005 | warning | adapter に宣言された inject がソース struct のフィールドに存在しない |
| S006 | info | operation の needs が構造体のフィールド/コンストラクタ引数に存在しない |

#### S003 の詳細: Op 照合ロジック

1. manifest の op 名を `naming.method_case` で変換
2. ソースの interface/trait のメソッド一覧と照合
3. 名前一致 → パラメータ数を検証 (S004)
4. `Error` 型は言語固有の慣習に従って照合:
   - Go: 戻り値リストの最後の `error` 型
   - TypeScript: `throws` annotation または戻り値型
   - Rust: `Result<T, E>` 戻り値型

### R0xx: Relation (関係チェック)

| Code | Severity | Condition |
|------|----------|-----------|
| R001 | error | adapter が `implements` で宣言した boundary を実装していない |
| R002 | warning | binding の adapter がソースに存在するが boundary を実装していない |

#### R001 の言語別判定

| Language | Implements の検出方法 |
|----------|---------------------|
| Go | adapter struct にレシーバメソッドがあり、boundary interface の全メソッドを充足している (duck typing) |
| TypeScript | `class Adapter implements Boundary` の `implements` 句 |
| Rust | `impl Boundary for Adapter` ブロックの存在 |

### T0xx: Drift (乖離検出, opt-in)

| Code | Severity | Condition |
|------|----------|-----------|
| T001 | info | layer ディレクトリにソース型が存在するが manifest に対応する宣言がない |
| T002 | info | ソース struct のフィールドが manifest に存在しない (余剰フィールド) |

drift チェックはデフォルト無効。`checks.drift = true` で有効化。

## 6. Report Format

### テキスト出力 (デフォルト)

```
plat-verify: order-service (go)

[E002] boundary OrderRepository not found
       expected: interface in domain/port/
       manifest: boundary with 4 ops (save, findById, findAll, delete)

[S001] model Order: missing field "shipping"
       expected: Address (in domain/order.go)

[R001] adapter PostgresOrderRepo does not implement OrderRepository
       missing methods: findAll, delete
       source: infra/postgres_order_repo.go:12

── Summary ──────────────────────────────────
  2 errors, 1 warning, 0 info
  declarations: 15 checked, 13 ok, 2 issues
  fields: 28 checked, 27 ok, 1 missing
  ops: 8 checked, 6 ok, 2 missing
```

### JSON 出力 (`--format json`)

```jsonc
{
  "name": "order-service",
  "language": "go",
  "findings": [
    {
      "code": "E002",
      "severity": "error",
      "declaration": "OrderRepository",
      "message": "boundary not found",
      "expected": { "kind": "boundary", "layer": "interface" },
      "source": null
    },
    {
      "code": "S001",
      "severity": "warning",
      "declaration": "Order",
      "message": "missing field \"shipping\"",
      "expected": { "field": "shipping", "type": "Address" },
      "source": { "file": "domain/order.go", "line": 12 }
    }
  ],
  "summary": {
    "errors": 2,
    "warnings": 1,
    "info": 0,
    "declarations": { "checked": 15, "ok": 13 },
    "fields": { "checked": 28, "ok": 27 },
    "ops": { "checked": 8, "ok": 6 }
  }
}
```

## 7. CLI Interface

```
plat-verify [OPTIONS] <MANIFEST>

Arguments:
  <MANIFEST>    manifest JSON ファイルのパス

Options:
  -c, --config <PATH>     設定ファイル (default: ./plat-verify.toml)
  -r, --root <DIR>        ソースルート (設定ファイルの source.root を上書き)
  -l, --language <LANG>   言語 (go|typescript|rust, 設定ファイルを上書き)
  -f, --format <FMT>      出力形式 (text|json, default: text)
      --check <CATEGORY>  有効にするチェックカテゴリ (複数指定可, e.g. --check existence --check structure)
      --severity <LEVEL>  表示する最低 severity (error|warning|info, default: info)
  -q, --quiet             summary のみ出力
  -v, --verbose           抽出した全 fact を表示 (デバッグ用)
  -h, --help
  -V, --version
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | 全チェック合格 (warning/info はあっても良い) |
| 1 | error が1つ以上ある |
| 2 | 入力エラー (manifest 読み込み失敗, 設定不正, ソースディレクトリ不在) |

### 使用例

```bash
# 基本: manifest と Go ソースの照合
plat-verify manifest.json --language go --root ./src

# 設定ファイルを使用
plat-verify manifest.json -c plat-verify.toml

# CI: JSON 出力 + error のみ
plat-verify manifest.json --format json --severity error

# plat と組み合わせ (パイプ)
cabal run my-arch -- --manifest | plat-verify /dev/stdin -l go -r ./src

# 存在チェックのみ
plat-verify manifest.json --check existence
```

## 8. Pipeline Integration

### plat 側の変更

manifest 出力を CLI から直接利用できるよう、plat の executable に `--manifest` フラグを追加するか、`renderManifest` の結果をファイルに書き出す関数を提供する。

```haskell
-- 既存 (変更不要)
manifest :: Architecture -> Manifest
renderManifest :: Manifest -> Text

-- 追加: ファイルに書き出す convenience
writeManifest :: FilePath -> Architecture -> IO ()
writeManifest fp = TIO.writeFile fp . renderManifest . manifest
```

### CI Pipeline 例

```yaml
# GitHub Actions
steps:
  - name: Generate manifest
    run: cabal run my-arch -- --manifest > manifest.json

  - name: Verify Go implementation
    run: plat-verify manifest.json -l go -r ./src --format json > verify.json

  - name: Check results
    run: |
      errors=$(jq '.summary.errors' verify.json)
      if [ "$errors" -gt 0 ]; then
        echo "Architecture conformance check failed"
        jq '.findings[] | select(.severity == "error")' verify.json
        exit 1
      fi
```

## 9. Implementation Notes

### 言語: Rust

- tree-sitter は Rust ネイティブ。tree-sitter crate + 各言語の grammar crate で依存解決
- serde で manifest JSON のデシリアライズ
- toml crate で設定ファイルのパース
- クロスプラットフォームバイナリ配布が容易

### 依存 crate (想定)

| Crate | 用途 |
|-------|------|
| `tree-sitter` | パーサランタイム |
| `tree-sitter-go` | Go grammar |
| `tree-sitter-typescript` | TypeScript grammar |
| `tree-sitter-rust` | Rust grammar |
| `serde`, `serde_json` | manifest JSON パース |
| `toml` | 設定ファイルパース |
| `clap` | CLI 引数パース |
| `walkdir` | ディレクトリ走査 |

### モジュール構成 (想定)

```
src/
  main.rs              -- CLI entry point
  config.rs            -- 設定ファイル読み込み
  manifest.rs          -- manifest JSON のデシリアライズ + 型定義
  extract/
    mod.rs             -- SourceFact 型定義 + language dispatch
    go.rs              -- Go tree-sitter extraction
    typescript.rs      -- TypeScript tree-sitter extraction
    rust.rs            -- Rust tree-sitter extraction
  check/
    mod.rs             -- Check engine + Finding 型
    existence.rs       -- E0xx checks
    structure.rs       -- S0xx checks
    relation.rs        -- R0xx checks
    drift.rs           -- T0xx checks
  report/
    mod.rs             -- Report dispatch
    text.rs            -- テキスト出力
    json.rs            -- JSON 出力
  naming.rs            -- 名前変換 (PascalCase, camelCase, snake_case)
  typemap.rs           -- 型マッピング + 比較
```

### tree-sitter クエリ例

**Go: struct フィールド抽出**

```scheme
(type_declaration
  name: (type_identifier) @type_name
  type: (struct_type
    (field_declaration_list
      (field_declaration
        name: (field_identifier) @field_name
        type: (_) @field_type))))
```

**Go: interface メソッド抽出**

```scheme
(type_declaration
  name: (type_identifier) @type_name
  type: (interface_type
    (method_spec
      name: (field_identifier) @method_name
      parameters: (parameter_list) @params
      result: (_)? @return_type)))
```

**TypeScript: interface メソッド抽出**

```scheme
(interface_declaration
  name: (type_identifier) @type_name
  body: (object_type
    (method_signature
      name: (property_identifier) @method_name
      parameters: (formal_parameters) @params
      return_type: (type_annotation)? @return_type)))
```

**Rust: trait メソッド抽出**

```scheme
(trait_item
  name: (type_identifier) @type_name
  body: (declaration_list
    (function_signature_item
      name: (identifier) @method_name
      parameters: (parameters) @params
      return_type: (type_identifier)? @return_type)))
```

## 10. Phases

### Phase 1: Foundation

- manifest パース + 設定読み込み
- Go の fact extraction (struct, interface, imports)
- E0xx (existence) + S0xx (structure) チェック
- テキストレポート出力

### Phase 2: Full Language Support

- TypeScript, Rust の fact extraction
- R0xx (relation) チェック
- JSON レポート出力
- CI integration examples

### Phase 3: Advanced

- T0xx (drift) チェック
- `--watch` モード (ファイル変更時に自動再検証)
- LSP 連携のための finding 出力 (Diagnostic 互換形式)
- パフォーマンス最適化 (incremental parsing, キャッシュ)

## 11. Scope Boundary

plat-verify が**やること**:

- manifest と source の構造照合
- 宣言の存在・フィールド・メソッド・関係の検証
- 設定可能な severity と check category
- 人間可読 + 機械可読の出力

plat-verify が**やらないこと**:

- コンパイル/ビルド (各言語のツールチェーンの責務)
- import 制限の強制 (`DepRules` が linter 設定を生成する)
- テスト実行 (`Target.*.contract` が test skeleton を生成する)
- ソースコード生成 (`Target.*.skeleton` の責務)
- アーキテクチャ定義 (plat eDSL の責務)
- 型の意味的等価判定 (名前ベースの一致のみ)

## 12. Known Limitations

### 名前変換

- **Go の略語慣習**: Go は `ID`, `URL`, `HTTP` 等の略語を全大文字にする慣習がある。plat-verify の PascalCase 変換は `id` → `Id` を生成するため、Go の `ID` とは一致しない。現時点ではワークアラウンドとして `[naming]` で case チェックを緩めるか、manifest 側で Go の命名に合わせる必要がある
- **言語固有の予約語**: manifest の名前がターゲット言語の予約語と衝突する場合のエスケープは未対応

### 型マッピング

- **名前ベースの一致のみ**: 型の構造的等価性は判定しない。`types` マッピングに登録されていないユーザー定義型は名前の完全一致で照合される
- **ジェネリクスのネスト**: `List<Option<T>>` のような入れ子ジェネリクスの型マッピングは外側のみ変換される（内側の型引数はそのまま比較）

### tree-sitter 抽出

- **Go: `method_elem` vs `method_spec`**: tree-sitter-go v0.23 で interface メソッドのノード名が `method_spec` から `method_elem` に変更された。plat-verify は両方を受け入れる
- **Go: 簡易型宣言**: `type Foo string` のような named type は fieldless struct として抽出される。enum/const group の意味的区別は行わない
- **TypeScript: `type` alias**: `type Foo = { ... }` 形式の型エイリアスは未抽出（`interface` と `class` のみ対応）
- **Rust: enum variants**: Rust の `enum` からのバリアント抽出は未対応

### チェック

- **Go の duck typing**: R001 (implements) チェックで Go の暗黙的インターフェース実装の検出は、メソッドシグネチャの完全一致ではなくメソッド名の存在のみで判定する
- **T0xx (drift)**: 実装済みだがデフォルト無効。大規模コードベースでの誤検出率は未検証

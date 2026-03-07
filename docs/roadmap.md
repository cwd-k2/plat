# Roadmap

plat の開発ロードマップ。完了済みのフェーズと今後の方向性。

## Completed

### v0.6.0: Core eDSL

- `Decl k` phantom-tagged newtype + `Declaration` untagged の2層設計
- `DeclWriter k` / `ArchBuilder` による State モナドベースの eDSL
- 5種の DeclKind: Model, Boundary, Operation, Adapter, Compose
- TypeExpr: ビルトイン型、ジェネリクス、nullable、ref、ext
- 11 検証ルール (V001-V008, W001-W003) via PlatRule + SomeRule
- 2 出力フォーマット: Mermaid, Markdown

### v0.6.0: Extensions

meta ベースの拡張メカニズム。core の DeclItem を変更せず、smart constructor + meta タグで語彙を追加。

- DDD: value, aggregate, enum\_, invariant
- CQRS: command, query
- CleanArch: entity, port, impl\_, wire + preset layers
- Http: controller, route
- DBC: pre, post, assert\_
- Flow: step, policy, guard\_
- Events: event, emit, on\_, apply\_
- Modules: domain, expose, import\_

### Target Language Generation

Architecture からターゲット言語のコードを生成する `Plat.Target.*` モジュール。

| Function | 目的 |
|----------|------|
| `skeleton` | 型定義、インターフェース、ユースケース構造体、アダプタスタブの生成 |
| `contract` | boundary ごとの契約テスト生成。adapter が op を満たすことを検証 |
| `verify` | コンパイル時適合チェック。ビルドが通れば Architecture に適合 |

対応言語: Go, TypeScript, Rust

### Verification Infrastructure

Architecture と実装の乖離を検出するための基盤。

- **Manifest** (`Plat.Verify.Manifest`): Architecture から言語非依存の JSON マニフェストを生成。型名、フィールド、インターフェース、メソッドシグネチャ、レイヤー配置、バインディングを記述
- **DepRules** (`Plat.Verify.DepRules`): レイヤー依存定義から linter 設定を導出
  - Go: golangci-lint depguard 設定
  - TypeScript: eslint-plugin-boundaries 設定
  - 汎用: 依存マトリクス (人間可読)

### plat-verify (Rust)

manifest と実装ソースの構造的適合性を検証するスタンドアロンツール。

- tree-sitter ベースの fact extraction (Go, TypeScript, Rust)
- 5カテゴリのチェック: E0xx (existence), S0xx (structure), R0xx (relation), T0xx (drift), L0xx (layer deps)
- テキスト / JSON レポート出力
- `--check` CLI フラグによるカテゴリ単位の有効化
- `--check` フラグで CI パイプラインに適合性ゲートを組み込み可能
- `layer_match = "component"` による feature-first ディレクトリレイアウト対応
- ファイルレベルのインクリメンタルキャッシュ (mtime + size ベース)

### Examples

4つのアーキテクチャパターンを plat で記述し、各ターゲット言語で実装:

| Example | Pattern | Language | Extensions |
|---------|---------|----------|------------|
| GoCleanArch | Clean Architecture | Go | CleanArch, DDD, Http |
| GoFeatureSliced | Feature-Sliced CA | Go | CleanArch, Modules |
| TsHexagonal | Hexagonal | TypeScript | Core only |
| RustCqrsEs | CQRS + Event Sourcing | Rust | CQRS, Events, DDD, Flow |

各 example は `Arch/` モジュール階層で構造化され、生成物を `dist/` に出力する。

## Future Directions

### Verification の深化

- **Import graph analysis**: Go の import、TS の import/require、Rust の use を解析し、レイヤー依存違反を検出。DepRules の linter 設定生成とは別に、plat-verify 自身がチェックする方向
- **`--watch` モード**: ファイル変更時に自動再検証
- **LSP 連携**: finding 出力を Diagnostic 互換形式にし、エディタ統合

### Code Generation の拡充

- **型マッピングのカスタマイズ強化**: TypeExpr → 言語型のマッピングをユーザー定義可能に（現在は Config の Map で対応）
- **import 文の自動生成**: skeleton 生成時にパッケージ間の参照を解決して import を出力
- **追加言語**: Python, Java, Kotlin, Swift など
- **テンプレートエンジン連携**: skeleton を mustache/tera 等のテンプレートから生成するオプション

### Architecture as Code の進化

- **Diff / Migration**: Architecture 値の差分検出。v1 → v2 でどの boundary に op が追加されたか、どの adapter が追加されたかを構造的に出力
- **REPL 統合**: `cabal repl` で Architecture を対話的に構築・検証・可視化
- **Multi-service**: 複数 Architecture 間の境界 (API contract) を記述し、サービス間整合性を検証
- **Bidirectional sync**: 実装コードから Architecture を逆生成 (extract) し、宣言と照合

### Extension の発展

- **拡張ルールの充実**: 現在空の `cqrsRules`, `flowRules`, `eventsRules`, `modulesRules` に実質的な検証を追加
  - CQRS: query が write 系 boundary を needs していないか
  - Events: emit されたイベントに対応する handler が存在するか
  - Modules: expose されていない宣言が外部から参照されていないか
- **カスタムルール API**: ユーザーが PlatRule を実装せずとも、宣言的にルールを記述できる DSL

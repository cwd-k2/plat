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

方針の詳細は [docs/tooling-direction.md](tooling-direction.md) を参照。

### Haskell / Rust 責務分離

Haskell はアーキテクチャそのもの（構築・検証・manifest 生成）を担い、Rust はプロジェクト内の言語の中身の読み書きを担う。manifest JSON が両者の安定境界となる。

- **Plat.Target.* の Rust 移行**: `skeleton`, `contract`, `verify` を Rust ツール群に段階的に移行し、Haskell 側は非推奨 → 削除
- **Plat.Verify.DepRules の Rust 移行**: linter 設定生成を `plat-deprules` として独立

### Rust ツール群の拡充

manifest を入力として各ツールが独立に動作する。各ツールは manifest の部分集合だけを消費する。

- **plat-skeleton**: コードスカフォールド生成。manifest の拡張 (operation の input/output 詳細、ext 型情報等) と合わせて進める
- **plat-contract**: boundary の ops からテストスケルトンを生成
- **plat-deprules**: レイヤー依存定義から linter 設定を導出 (最も単純、移行の最初の候補)
- **共通 crate 抽出**: plat-verify から `plat-manifest`, `plat-naming`, `plat-typemap` を分離し、ツール間で共有

### plat-verify の深化

- **Import graph analysis**: ソースの import/use からレイヤー依存違反を検出
- **`--watch` モード**: ファイル変更時に自動再検証
- **LSP 連携**: finding を Diagnostic 互換形式で出力しエディタ統合

### Architecture as Code の進化

- **Diff / Migration**: Architecture 値の差分検出。v1 → v2 で何が変わったかを構造的に出力
- **REPL 統合**: `cabal repl` で Architecture を対話的に構築・検証・可視化
- **Multi-service**: 複数 Architecture 間の境界 (API contract) を記述し、サービス間整合性を検証

### Extension の発展

- **拡張ルールの充実**: 現在空の `cqrsRules`, `flowRules`, `eventsRules`, `modulesRules` に実質的な検証を追加
  - CQRS: query が write 系 boundary を needs していないか
  - Events: emit されたイベントに対応する handler が存在するか
  - Modules: expose されていない宣言が外部から参照されていないか
- **カスタムルール API**: ユーザーが PlatRule を実装せずとも、宣言的にルールを記述できる DSL

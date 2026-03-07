# Roadmap

plat の開発ロードマップ。完了済みのフェーズと今後の方向性。

## Completed

### Core eDSL (v0.6.0)

- `Decl k` phantom-tagged newtype + `Declaration` untagged の2層設計
- `DeclWriter k` / `ArchBuilder` による State モナドベースの eDSL
- 5種の DeclKind: Model, Boundary, Operation, Adapter, Compose
- TypeExpr: ビルトイン型、ジェネリクス、nullable、ref、ext (`TExt`)
- 14 検証ルール (V001-V009, W001-W004) via PlatRule + SomeRule
- 2 出力フォーマット: Mermaid, Markdown

### Extensions (v0.6.0)

meta ベースの拡張メカニズム。core の DeclItem を変更せず、smart constructor + meta タグで語彙を追加。

- DDD: value, aggregate, enum, invariant + DDD-V001, DDD-V002
- CQRS: command, query + CQRS-W001
- CleanArch: entity, port, impl, wire + CA-V001, CA-W001
- Http: controller, route + HTTP-W001
- DBC: pre, post, assert_ + DBC-W001
- Flow: step, policy, guard_
- Events: event, emit, on_, apply + EVT-V001, EVT-W001, EVT-W002
- Modules: domain, expose, import_ + MOD-V001, MOD-V002, MOD-W001
- **MultiService**: system, include, serviceApi, serviceRequires + SVC-V001, SVC-V002, SVC-W001

### Architecture Algebra (v0.6.0)

- `merge` / `mergeAll`: 互換性チェック付き合成 (`Either [Conflict] Architecture`)
- `isCompatible`: 明示的な互換性チェック
- `project` / `projectLayer` / `projectKind`: 射影
- `diff`: 構造差分 (Added / Removed / Modified)
- 代数的性質 (結合律、冪等性、単位元) をテストで検証

### Constraint System (v0.6.0)

- `ArchConstraint` + `constrain` でアーキテクチャレベルの制約を一級値として登録
- 述語コンビネータ: `require`, `forbid`, `forAll`, `holds`
- 合成コンビネータ: `both`, `allOf`, `oneOf`, `neg`
- プリセット制約: `operationNeedsBoundary`, `unwiredBoundaries`, `noNeedsCycle`

### Relation Graph (v0.6.0)

- 暗黙的関係 (DeclItem 由来) + 明示的関係 (`relate`) の統一グラフ
- クエリ: `relations`, `relationsOf`, `dependsOn`, `implementedBy`, `boundTo`
- グラフ走査: `transitive`, `reachable`, `isAcyclic`
- `typeRefs`: TypeExpr から TRef 名を再帰的に抽出 (TExt は除外)

### Verification Infrastructure

- **Manifest** (`Plat.Verify.Manifest`): Architecture → JSON manifest (仕様: [docs/spec/manifest.md](spec/manifest.md))
- **Custom rule API**: `mkDeclRule`/`mkArchRule` でクロージャベースのカスタムルール作成
- **Golden tests**: Haskell → manifest → Rust の cross-language テストパイプライン

### plat-verify (Rust)

- tree-sitter ベースの fact extraction (Go, TypeScript, Rust)
- 7カテゴリのチェック: E0xx, S0xx, R0xx, T0xx, L0xx, I0xx, N0xx
- 3 出力フォーマット: text, JSON, LSP diagnostics
- ファイルレベルのインクリメンタルキャッシュ
- Import graph analysis: I001 (レイヤー越えインポート), I002 (インポートサイクル)
- Naming convention checks: N001 (型名), N002 (フィールド名), N003 (メソッド名)
- `--watch` モード (notify ベース、debounce 付きファイル監視)
- `--lsp` モード (lsp-server crate, didSave → publishDiagnostics)
- LSP diagnostics 出力 (`--format lsp` でバッチ出力も可能)

### Rust ツール群

- **plat-skeleton**: コードスカフォールド生成 (Go/TS/Rust 生成テスト付き)
- **plat-contract**: boundary の ops からテストスケルトン生成 (Go/TS/Rust 生成テスト付き)
- **plat-deprules**: レイヤー依存定義から linter 設定を導出 (matrix/depguard/eslint テスト付き)
- **plat-repl**: manifest ベースの対話シェル (decls, show, deps, layers, stats 等)

### Editor Integration

- **VS Code extension** (`editors/vscode`): plat-verify LSP client, 自動 manifest 検出, ステータスバー表示

## Future Directions

方針の詳細は [docs/tooling-direction.md](tooling-direction.md) を参照。

### Architecture as Code の進化

- plat-repl の拡張 (check コマンド, diff コマンド, mermaid 出力)
- Multi-service manifest 生成 (system-level manifest)
- VS Code extension の publish (VSIX パッケージ化)

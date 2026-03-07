# Roadmap

plat の開発ロードマップ。完了済みのフェーズと今後の方向性。

## Completed

### Core eDSL (v0.6.0)

- `Decl k` phantom-tagged newtype + `Declaration` untagged の2層設計
- `DeclWriter k` / `ArchBuilder` による State モナドベースの eDSL
- 5種の DeclKind: Model, Boundary, Operation, Adapter, Compose
- TypeExpr: ビルトイン型、ジェネリクス、nullable、ref、ext (`TExt`)
- 14 検証ルール (V001-V009, W001-W004) via PlatRule + SomeRule
- ~~2 出力フォーマット: Mermaid, Markdown~~ → plat-doc (Rust) に移行済み

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

- **plat-doc**: manifest → Markdown/Mermaid/DSM 生成 (Haskell Generate を廃止・Rust に移行)
- **plat-skeleton**: コードスカフォールド生成 (Go/TS/Rust 生成テスト付き)
- **plat-contract**: boundary の ops からテストスケルトン生成 (Go/TS/Rust 生成テスト付き)
- **plat-deprules**: レイヤー依存定義から linter 設定を導出 (matrix/depguard/eslint テスト付き)
- **plat-repl**: manifest ベースの対話シェル (decls, show, deps, layers, stats 等)

### Editor Integration

- **VS Code extension** (`editors/vscode`): plat-verify LSP client, 自動 manifest 検出, ステータスバー表示

### Advanced Verification Modes

- **`--suggest`**: drift findings (T001-T003) から manifest パッチ JSON を生成
- **`--contracts`**: 2 manifest 間の契約互換性検証 (CT001-CT003)
- **`--init`**: tree-sitter facts → 初期 manifest JSON 逆生成 (Reflexion Model bootstrapping)
  - Kind inference: boundary (interface/trait), adapter (implements), operation (boundary-typed fields), model (default)
  - Go structural typing: method-set superset による暗黙的 implements 検出
  - Layer dependency inference: cross-layer 参照からの自動推論
- **Convergence / Health Score**: types, fields, methods の確認率を weighted score で表示

### Infrastructure

- ~~plat-doc~~ ✓ manifest → Markdown/Mermaid/DSM 生成 (Rust ツール化完了)
- ~~Drift 詳細化~~ ✓ T003 (余剰メソッド), T004 (未宣言 implements)
- ~~キャッシュバージョニング~~ ✓ パーサー変更時の stale cache 防止
- ~~Multi-service manifest~~ ✓ Haskell service フィールド出力 + Rust split_by_service
- ~~Import graph analysis~~ ✓ I001 (レイヤー越えインポート), I002 (サイクル)
- ~~Naming convention checks~~ ✓ N001-N003
- ~~find_type_by_name 統一~~ ✓ 全チェッカーで共通の型検索関数 (Go suffix match, original name fallback)

## Future Directions

方針の詳細は [docs/tooling-direction.md](tooling-direction.md) を参照。

- VS Code extension の publish (VSIX パッケージ化)

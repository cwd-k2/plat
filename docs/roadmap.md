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
- CQRS: command, query
- CleanArch: entity, port, impl, wire + CA-V001, CA-W001
- Http: controller, route + HTTP-W001
- DBC: pre, post, assert_ + DBC-W001
- Flow: step, policy, guard_
- Events: event, emit, on_, apply + EVT-V001, EVT-W001
- Modules: domain, expose, import_ + MOD-V001, MOD-V002

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

- **Manifest** (`Plat.Verify.Manifest`): Architecture → JSON manifest
- **plat-verify** (Rust): manifest と実装の構造的適合性検証

### plat-verify (Rust)

- tree-sitter ベースの fact extraction (Go, TypeScript, Rust)
- 5カテゴリのチェック: E0xx, S0xx, R0xx, T0xx, L0xx
- テキスト / JSON レポート出力
- ファイルレベルのインクリメンタルキャッシュ

## Future Directions

方針の詳細は [docs/tooling-direction.md](tooling-direction.md) を参照。

### Haskell / Rust 責務分離

- **Plat.Target.* の Rust 移行**: `skeleton`, `contract`, `verify` を Rust ツール群に段階的に移行
- **Plat.Verify.DepRules の Rust 移行**: linter 設定生成を `plat-deprules` として独立

### Rust ツール群の拡充

- **plat-skeleton**: コードスカフォールド生成
- **plat-contract**: boundary の ops からテストスケルトンを生成
- **plat-deprules**: レイヤー依存定義から linter 設定を導出

### plat-verify の深化

- Import graph analysis
- `--watch` モード
- LSP 連携

### Architecture as Code の進化

- REPL 統合
- Multi-service (複数 Architecture 間の境界)

### Extension の発展

- CQRS: query が write 系 boundary を needs していないか
- Events: emit されたイベントに対応する handler が存在するか
- Modules: expose されていない宣言が外部から参照されていないか
- カスタムルール API

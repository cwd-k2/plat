# plat

Haskell eDSL でソフトウェアアーキテクチャを記述するライブラリ。

## Core Concept

`Decl k` (phantom-tagged) と `Declaration` (untagged) の2層設計。
構築時はコンパイル時型安全性、操作時は均質なデータ型として扱う。

- `Decl k` → eDSL の表面。`DeclWriter k` の phantom パラメータがコンビネータを制約する
- `Declaration` → AST の内部表現。check / generate はすべてこのレベルで動作する
- `decl :: Decl k -> Declaration` で消去。逆方向 (Declaration → Decl k) は存在しない

## Key Decisions

- **mtl 非依存**: DeclWriter / ArchBuilder は手動 State モナド (Functor/Applicative/Monad を手動実装)
- **DeclItem は閉じている**: 拡張は `meta` タグで実現。新しい DeclItem コンストラクタは追加しない
- **Meta DSL (`Plat.Core.Meta`)**: 拡張は raw `meta` ではなく `tagAs`/`annotate`/`refer`/`attr` で構築する。内部表現は `[(Text, Text)]` のまま
- **PlatRule + SomeRule**: 検証ルールは type class + 存在型 GADT で合成可能
- **GHC2024**: DataKinds, GADTs, DerivingStrategies が暗黙的に有効
- **ArchConstraint は関数を含む**: `acCheck :: Architecture -> [Text]` のため Show/Eq は `acName` ベースの手動実装。Architecture は deriving stock を維持
- **Relation は Architecture レベル**: DeclItem を閉じたまま、明示的関係は `archRelations` + `relate` で表現。暗黙的関係 (needs, implements 等) は `relations` 関数で統合ビュー化
- **Architecture 代数**: `merge` は互換性チェック付き (`Either [Conflict] Architecture`)。`project` はフィルタ + 孤立 Relation 除去
- **TExt**: `ext` は `TExt` コンストラクタを生成。`TRef` とは異なり W002 対象外、`typeRefs` からも除外

## Pitfalls

- **V007 の暗黙カバー**: adapter に Op がなければ boundary の全 op を暗黙カバーとみなす。plat の adapter は boundary の op を再宣言しない設計のため
- **W002 と ext/inject**: `TExt` は W002 検査から除外される。`Inject` 内の `TRef` も除外
- **Text vs String**: render / prettyCheck は `Text` を返す。`putStrLn` ではなく `Data.Text.IO.putStrLn` を使う
- **`result` の名前衝突**: `Plat.Core` が `result :: TypeExpr -> TypeExpr -> TypeExpr` をエクスポートする。ローカル変数名に注意
- **W003/W004**: W003 は多重 implements、W004 はファイル不在 (IO)

## Building

```
cabal build          # Haskell ビルド
cabal test           # Haskell テスト
cabal build --ghc-options=-Werror  # Haskell lint
cargo build          # Rust ツール群ビルド
cargo test           # Rust テスト
```

mise タスクも利用可能 (`mise run build`, `mise run test` 等)。

## Adding a Validation Rule

1. `src-hs/Plat/Check/Rules.hs` に data 型を定義
2. `PlatRule` instance を実装 (`ruleCode`, `checkDecl` or `checkArch`)
3. `coreRules` リストに `SomeRule NewRule` を追加
4. `test/hs/Main.hs` にテスト追加

拡張固有ルールは各 `Ext/*.hs` で定義し、`{ext}Rules :: [SomeRule]` としてエクスポート。

## Adding an Extension

1. `src-hs/Plat/Ext/NewExt.hs` を作成
2. `ExtId` を定義: `newext = extId "newext"`
3. `MetaTag` を定義: `newextFoo = kind newext "foo"`
4. Smart constructor: core コンストラクタ + `tagAs newextFoo` のラッパー
5. Query helper: `isTagged`/`annotations`/`references` ベースの述語
6. ルール (任意): `newextRules :: [SomeRule]`
7. `plat.cabal` の `exposed-modules` に追加

Meta DSL の4パターン:
- `tagAs tag` — 宣言の分類 (kind tag)
- `attr ext key val` — 単純属性
- `annotate ext cat name val` — 名前付き注釈
- `refer ext cat decl` — 他宣言への参照

詳細: [docs/extensions.md](docs/extensions.md)

## Adding a Generator

`Architecture -> Text` 関数を `src-hs/Plat/Generate/` に追加。
`archDecls` を走査し、`declKind` / `declBody` / `declMeta` を読んで出力を構築する。

## Rust ツール群

言語の中身の読み書きは Rust ツールが担う。Haskell は manifest 生成まで。
詳細は [docs/tooling-direction.md](docs/tooling-direction.md) を参照。

| ツール | 用途 | 入力 |
|--------|------|------|
| `plat-verify` | 構造適合性検証 | manifest + ソースコード |
| `plat-verify --suggest` | manifest パッチ提案 | manifest + ソースコード |
| `plat-verify --contracts` | manifest 間互換性検証 | manifest × 2 |
| `plat-verify --init` | ソースから manifest 逆生成 | ソースコードのみ |
| `plat-doc` | ドキュメント生成 (Markdown/Mermaid/DSM) | manifest |
| `plat-skeleton` | コードスカフォールド生成 | manifest |
| `plat-contract` | テストスケルトン生成 | manifest |
| `plat-deprules` | linter 依存ルール生成 | manifest |

Rust コードは `crates/` 配下に Cargo workspace として構成。共通型は `plat-manifest` crate。
manifest JSON format は [docs/spec/manifest.md](docs/spec/manifest.md) で正式に仕様化。
`test/golden/manifest.json` がゴールデンテストファイルとして Haskell/Rust 両方で検証される。

```
cargo build                    # 全ツールビルド
cargo test -p plat-manifest    # 共通 crate テスト (ゴールデンテスト含む)
cargo test -p plat-verify      # verify テスト
```

## Testing

テストは `test/hs/` 配下にモジュール分割:
- `Test.Core` — core eDSL, check, manifest
- `Test.Ext` — 全拡張モジュール
- `Test.Constraint` — 制約システム
- `Test.Relation` — 関係グラフ
- `Test.Algebra` — Architecture 代数
- `Test.Evidence` — CheckEvidence, 代数的性質
- `Test.Manifest` — manifest round-trip + ゴールデンファイル生成
- `Test.Fixtures` — 共有テストデータ
- `Test.Harness` — テストランナー

テストフレームワークは未使用 (base のみ)。`runTests` は自前実装。

## Reference

- [docs/spec/](docs/spec/) — 正式仕様 (体系的に分割)
- [docs/architecture.md](docs/architecture.md) — モジュール構成、AST 設計、モナド設計の詳細
- [docs/validation-rules.md](docs/validation-rules.md) — V001-V010, W001-W004 の詳細仕様
- [docs/extensions.md](docs/extensions.md) — 拡張の設計パターンと全拡張の meta タグ一覧
- [docs/plat-verify-spec.md](docs/plat-verify-spec.md) — plat-verify 仕様
- [docs/tooling-direction.md](docs/tooling-direction.md) — Haskell/Rust 責務分離の方針

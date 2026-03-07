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
- **Architecture 代数**: `merge` は左優先で名前ベース重複排除。`project` はフィルタ + 孤立 Relation 除去

## Pitfalls

- **V007 の暗黙カバー**: adapter に Op がなければ boundary の全 op を暗黙カバーとみなす。plat の adapter は boundary の op を再宣言しない設計のため
- **W002 と ext/inject**: `Inject` 内の `TRef` は W002 検査から除外される (`ext` で指定される外部型)
- **Text vs String**: render / prettyCheck は `Text` を返す。`putStrLn` ではなく `Data.Text.IO.putStrLn` を使う
- **`result` の名前衝突**: `Plat.Core` が `result :: TypeExpr -> TypeExpr -> TypeExpr` をエクスポートする。ローカル変数名に注意

## Building

```
cabal build          # Haskell ビルド
cabal test           # Haskell テスト (162 tests)
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
| `plat-skeleton` | コードスカフォールド生成 | manifest |
| `plat-contract` | テストスケルトン生成 | manifest |
| `plat-deprules` | linter 依存ルール生成 | manifest |

Rust コードは `crates/` 配下に Cargo workspace として構成。共通型は `plat-manifest` crate。

```
cargo build                    # 全ツールビルド
cargo test -p plat-manifest    # 共通 crate テスト
cargo test -p plat-verify      # verify テスト
```

## Testing

`test/hs/Main.hs` に全テストがフラットに配置されている。
テストフレームワークは未使用 (base のみ)。`assertEqual` / `assertBool` は自前実装。

## Target Language Modules (Plat.Target.*)

`Plat.Target.{Go,TypeScript,Rust}` はターゲット言語向けのコード生成。

各モジュールが `skeleton`, `contract`, `verify` の3関数をエクスポートする。
シグネチャは共通: `Config -> Architecture -> [(FilePath, Text)]`

### 新しい Target 言語を追加するとき

1. `src-hs/Plat/Target/NewLang.hs` を作成
2. `LangConfig` 型を定義 (型マッピング、レイヤー→ディレクトリ対応)
3. `TypeExpr -> Text` の型マッピングを実装
4. `skeleton`: Model → struct/interface, Boundary → interface/trait, Operation → class/fn, Adapter → impl
5. `contract`: Boundary ごとにテストスケルトン生成
6. `verify`: adapter implements boundary のコンパイル時検証コード生成
7. `plat.cabal` に追加

### 注意点

- `ext` 型はターゲット言語固有なのでパススルー (型マッピングをバイパス)
- `isErrorType` で Error を特別扱い (Go: error 戻り値、TS: throw、Rust: Result)
- レイヤー名 → パッケージ/ディレクトリ名のマッピングは Config で上書き可能

## Reference

- [docs/architecture.md](docs/architecture.md) — モジュール構成、AST 設計、モナド設計の詳細
- [docs/validation-rules.md](docs/validation-rules.md) — V001-V009, W001-W003 の詳細仕様
- [docs/extensions.md](docs/extensions.md) — 拡張の設計パターンと全拡張の meta タグ一覧
- [docs/plat-verify-spec.md](docs/plat-verify-spec.md) — plat-verify 仕様
- [docs/tooling-direction.md](docs/tooling-direction.md) — Haskell/Rust 責務分離の方針
- [docs/spec-v0.6.md](docs/spec-v0.6.md) — 正式仕様

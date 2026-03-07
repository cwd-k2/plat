# plat 仕様

**バージョン**: 0.6.0
**最終更新**: 2026-03-07

## 概要

plat は Haskell eDSL によるソフトウェアアーキテクチャ記述ライブラリである。

**ねらい**: 実装言語・フレームワーク・ディレクトリ構造といった実装上の関心事から**設計・アーキテクチャだけを抽出**し、「何がどのレイヤーにあり、何が何に依存しているか」という構造の検討に専念できる環境を提供する。

## 設計方針

| 方針 | 内容 |
|------|------|
| **H1** | Plat 仕様への忠実性 |
| **H2** | 値による参照 — 宣言間の参照はすべて Haskell の変数束縛。文字列は命名とパスに限定 |
| **H3** | 宣言の二層モデル — `Decl k` (phantom-tagged) で構築時の型安全性、`Declaration` で操作時の均質性 |
| **H4** | 名前は宣言に属し、参照は値に属す |
| **H5** | 型も値 — ビルトイン型・model 参照・カスタム型をすべて `TypeExpr` の値として提供 |
| **H6** | 生成物としての .plat — 生成された `.plat` は手書きと区別がつかない |
| **H7** | 柔軟な構造パターン — adapter は HTTP ハンドラ等の入口コンポーネントも表現可能 |

## データフロー

```
ユーザーの .hs
    │  import Plat.Core
    ▼
eDSL 式（Decl k + do 記法 + constrain / relate）
    │
    ▼
Architecture（AST: Declaration + ArchConstraint + Relation）
    │
    ├──→ check / checkWith ──→ CheckResult（ルール + 制約評価）
    ├──→ relations         ──→ [Relation]（統一グラフ）
    ├──→ merge / project   ──→ Architecture（合成・射影）
    ├──→ diff              ──→ ArchDiff（構造差分）
    ├──→ manifest          ──→ JSON（Rust ツール群への入力）
    ├──→ renderMermaid     ──→ Text
    └──→ renderMarkdown    ──→ Text
```

## 仕様書構成

| ファイル | 内容 |
|----------|------|
| [ast.md](ast.md) | AST — DeclKind, Declaration, TypeExpr, DeclItem |
| [builder.md](builder.md) | ビルダーモナド — DeclWriter, ArchBuilder, 宣言構文 |
| [type-system.md](type-system.md) | 型式システム — ビルトイン型, 参照, 外部型 |
| [validation.md](validation.md) | 検証システム — 全ルール一覧 (V001-V009, W001-W004, 拡張ルール) |
| [extensions.md](extensions.md) | 拡張システム — Meta DSL, 全8拡張モジュール |
| [constraint.md](constraint.md) | 制約システム — ArchConstraint, 述語コンビネータ, プリセット |
| [relation.md](relation.md) | 関係グラフ — 暗黙的/明示的関係, グラフ走査 |
| [algebra.md](algebra.md) | Architecture 代数 — merge, project, diff |

## なぜ Haskell か

| 要件 | Haskell の対応 |
|------|---------------|
| 宣言間の参照安全性 | 変数束縛がそのまま参照グラフになる |
| 宣言種の構造安全性 | phantom type + kind promotion |
| 宣言的な設計記述 | do 記法 |
| 検証ルールの合成・拡張 | 型クラス + 代数的データ型 |
| パッケージ拡張 | Haskell モジュール + 型クラスインスタンス |
| メタプログラミング | 通常の関数・リスト操作 |

## GHC 要件

**推奨**: GHC 9.10 以上 (GHC2024)

ユーザーに要求する言語拡張は `OverloadedStrings` のみ。型注釈で `Decl 'Model` 等を書く場合は `DataKinds` が必要だが、GHC2024 では標準で有効。

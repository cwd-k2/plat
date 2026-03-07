# Tooling Direction

plat プロジェクトにおける Haskell と Rust の責務分離。

## 原則

**Haskell はアーキテクチャそのものを扱い、Rust はプロジェクト内の言語の中身を読み書きする。**

| | Haskell (plat ライブラリ) | Rust (plat-* ツール群) |
|---|---|---|
| 対象 | アーキテクチャという抽象 | プロジェクトという実体 |
| 操作 | 構築・検証・変換 | 読み取り・生成・書き込み |
| 性質 | 純粋・閉じた世界 | I/O・外界と接触する |
| 出力 | manifest (JSON) | ファイル・レポート |

## manifest が安定境界

Haskell と Rust の接点は manifest JSON ただ一つ。

```
Haskell (plat)
    |
    |  Architecture -> Manifest -> JSON
    |
    v
 manifest.json
    |
    |---> plat-verify       構造適合性の検証
    |---> plat-skeleton     コードスカフォールド生成
    |---> plat-contract     テストスケルトン生成
    |---> plat-deprules     linter 依存ルール生成
    '---> plat-*            将来のツール
```

- Haskell 側の責務は「Architecture を記述・検証し、manifest を吐く」こと
- manifest から先は全て Rust ツール群の仕事
- 各ツールは manifest の部分集合だけを消費し、知らないフィールドは無視する

### 各ツールが知るべきこと

| ツール | manifest から読むもの |
|--------|----------------------|
| plat-verify | kind, layer, fields, ops, implements, bindings |
| plat-skeleton | kind, layer, fields, ops, needs, implements, injects |
| plat-contract | boundary の ops, bindings |
| plat-deprules | layers (depends) |

## Haskell 側の構成

- **Core eDSL** (`Plat.Core.*`): 宣言の構築、型式、phantom-tagged 安全性
- **検証** (`Plat.Check.*`): PlatRule による意味的検証 (V001-V008, W001-W003)
- **拡張** (`Plat.Ext.*`): meta ベースの語彙拡張
- **出力生成** (`Plat.Generate.*`): Mermaid, Markdown — アーキテクチャの可視化
- **manifest 生成** (`Plat.Verify.Manifest`): Architecture -> JSON

`Plat.Target.*` および `Plat.Verify.DepRules` は Rust ツール群に移行済み。削除された。

## Rust ツール群の構成

Cargo workspace (`crates/`) として構成。

```
crates/
  plat-manifest/     共通: manifest 型定義、型マッピング、命名変換
  plat-verify/       構造適合性検証 (tree-sitter ベース)
  plat-skeleton/     コードスカフォールド生成
  plat-contract/     テストスケルトン生成
  plat-deprules/     linter 依存ルール生成
```

### 共通 crate: plat-manifest

全ツールが依存する共通の型定義と変換関数。

| モジュール | 内容 |
|-----------|------|
| `manifest` | Manifest, Declaration, DeclKind, Field, Op, Binding, Layer |
| `lang` | Language (Go/TypeScript/Rust), Case (Pascal/Camel/Snake) |
| `naming` | 命名規約変換 (`convert(name, case)`) |
| `typemap` | manifest 型 -> 言語型マッピング (`resolve`, `defaults`, `is_error_type`) |

### 設計方針

- 各ツールは独立したバイナリ。知っておくべきことを最小化する
- ツール単位でのリリース・更新が可能
- 新しいツールの追加が既存ツールに影響しない

## manifest スキーマの拡張

- フィールド追加のみ (削除・変更なし)
- 各ツールは未知のフィールドを無視する (open-world assumption)
- meta 情報を manifest に含めるかは、ツール側の需要に応じて判断する

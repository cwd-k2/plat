# plat 批判的レビュー

**日付**: 2026-03-07
**対象**: plat v0.6.0 (commit 31dc5c9)
**範囲**: Haskell eDSL 全体（Core, Check, Generate, Ext, Verify）、ドメイン知識との整合性

---

## 0. 前提

本レビューは plat の設計・実装を、蓄積されたドメイン知識（ADL の歴史と教訓、アーキテクチャパターン理論、Haskell eDSL 分析、依存型理論の適用可能性分析）と照合し、構造的な問題を特定する。技術的正確性だけでなく、プロジェクトとしての方向性にも踏み込む。

---

## 1. 想定ユーザーの不在

### 問題

plat の最も根本的な問題は、**誰がなぜ使うのか**の物語が欠けていること。

- spec-v0.6 の「なぜ Haskell か」は plat 開発者への正当化であって、ユーザーへの説得ではない
- 非 Haskell プロジェクト (Go, TS, Rust) のアーキテクチャを記述するために Haskell を学ぶ開発者はいるか？
- C4 / Structurizr DSL が「形式的厳密性を放棄してコミュニケーション効果を優先」して成功した教訓がある

### ドメイン知識との照合

ADL が実務で失敗した5つの教訓のうち、plat は以下に該当するリスクがある:
1. **学習コスト** — Haskell + phantom type + do 記法は高い
2. **ツールの未成熟** — Generate の大部分が未実装
3. **ライフサイクルへの非統合** — CI/CD への組み込みパスが不明確

### 本質的な問い

plat が解決する問題は、Structurizr DSL や C4 が解決できない問題か？ もし「Haskell の型安全性」が唯一の差別化要因なら、それは利用者にとっての価値ではなく、作者にとっての価値。

---

## 2. DeclItem の閉じ方の半端さ — 型安全性の二重基準

### 問題

「DeclItem は閉じている。拡張は `meta` タグで実現」という決定は、**型安全性の境界を不自然な位置に引いている**。

- 9つの DeclItem コンストラクタの選択基準が不明確
- `Inject` が DeclItem なのに `route` (HTTP) や `pre`/`post` (DBC) が meta である根拠がない
- meta は `[(Text, Text)]` — phantom tag で構築時の安全性を謳いながら、拡張の世界では文字列連結で名前空間を手動管理

### 帰結

拡張が増えるほど、安全でない meta の領域が支配的になる。システムの成長方向が、型安全な領域から離れていく構造。

### Perry & Wolf の Form の欠落

Architecture に Rationale（設計判断の根拠）を記録する仕組みがない。構造の骨格だけが残り、「なぜこの設計か」が失われる。

---

## 3. 拡張 (Ext) の空洞化

### 問題

8つの拡張モジュールのうち、実質的な検証ルールを持つのは DDD (2ルール) と DBC (1ルール) のみ。

| 拡張 | ルール数 | 状態 |
|------|---------|------|
| DDD | 2 (DDD-V001, DDD-V002) | 最低限の意味論あり |
| DBC | 1 (DBC-W001) | 最低限の意味論あり |
| CQRS | 0 | **語彙のみ** |
| Events | 0 | **語彙のみ** |
| Flow | 0 | **語彙のみ** |
| Modules | 0 | **語彙のみ** |
| Http | 0 | **語彙のみ** |
| CleanArch | 0 | **語彙のみ** |

ルールのない拡張の語彙は**検証されないコメント**に等しい。plat の価値が「構造の検証」にあるなら、語彙だけの拡張は実質的に無価値。

### 拡張パターンの画一性

ほぼ全ての smart constructor が同一パターン:

```haskell
foo name ly body = someConstructor name ly $ do
  tagAs fooTag
  body
```

これは「語彙の貼り付け」であって「意味論の追加」ではない。`command` と `query` の違いは meta タグの文字列値だけで、CQRS の本質的制約は強制されない。

---

## 4. 検証ルールの表現力の限界

### 問題

V001-V009 は全て構造的整合性チェック（参照解決、種類一致、重複検出）。これは ADL の基本機能。

### 欠けている検証の例

plat の差別化になりうる、より本質的な検証:

- 「application レイヤーの operation は少なくとも1つの boundary を needs すべき」
- 「adapter は2つ以上の boundary を同時に implements すべきでない」（SRP）
- 「Compose で bind されていない boundary が needs されている」（配線の完全性）
- 「循環する needs チェーン」（operation 間の依存サイクル）

これらは `constrain` で書けるが、ユーザーに委ねられている。プリセットとして提供すべきパターンがある。

---

## 5. Architecture 代数の不完全性

### merge の問題

- 同名宣言の body の差異を無視して左を採用 → **情報の暗黙的損失**
- `isCompatible` は提供されているが `merge` が内部で呼ばない → 不整合な merge が静かに成功する
- 「結合律は名前衝突なし時に成立」— 実用上ほぼ常に衝突がある大規模システムでは成立しない

### project の問題

- `relSource` だけ残り `relTarget` が除去された Relation は壊れた参照を含む
- Constraint はそのまま保持される — 射影後の Architecture に無意味な制約が残りうる

### 代数としての不備

merge の結合律が条件付き、冪等性は名前ベースのみ — モノイドの条件すら危うい。「代数」を名乗るなら性質の保証を型レベルまたはランタイムで強制すべき。あるいは正直に「構造的ユーティリティ」と呼ぶべき。

---

## 6. テストの質

### 量と表現力の乖離

- 162テストは量として妥当だが、自前ハーネス (base のみ) がテストの表現力を制限
- プロパティベーステスト (QuickCheck/Hedgehog) がないため、代数的性質は手書き具体例 3-4 個に限定
- `testAlgebraicProperties` は名前に反して代数的性質のテストではない — 名前集合の一致を見ているだけで、`declBody`, `declMeta`, `declPaths` の差異を検証していない

### テストのカバレッジ

- `testCheck` は `coreArch` が violation/warning なしであることだけ確認
- 各ルールの境界条件テストが不十分（偽陰性のリスク）

---

## 7. コード生成の中途半端さ

### 未実装のモジュール

- `Plat.Generate.Plat` — spec に記載あり、実装なし
- `Plat.Target.{Go,TypeScript,Rust}` — CLAUDE.md に記載あり、実装なし（または Rust 移行済み？）
- `Plat.Verify.DepRules` — roadmap に記載あり、実装なし

### Mermaid 生成の不完全さ

`sanitize` がスペースとハイフンのみ除去。括弧、ドット、スラッシュ等の特殊文字に未対応。

---

## 8. Haskell コードの技術的問題

### 8.1 renderTE の重複

`Plat.Core.TypeExpr.renderTypeExpr` と `Plat.Verify.Manifest.renderTE` が完全に同一のロジックを重複実装。

### 8.2 hasCycle の潜在的バグ

`Plat.Check.Rules` の `hasCycle` は DFS での `visited` 更新が `go` レベルでしか行われず、`dfs` の再帰から戻った後に `visited` が更新されない。コメント `-- (simplified: ...)` がバグの可能性を認めている。

### 8.3 O(n^2) の計算量

`relations`, `relationsOf`, `dependsOn`, `implementedBy`, `boundTo` が `relations a` を毎回再計算。`relations` は全宣言の全 DeclItem を走査するので O(n*m)。組み合わせ使用で O(n^2*m)。`transitive` / `reachable` も各ステップでリニアサーチ。

### 8.4 ext と customType の区別の無意味さ

```haskell
ext :: Text -> TypeExpr
ext = TRef

customType :: Text -> TypeExpr
customType = TRef
```

同一の実装。区別は呼び出し側の意図にしか存在せず、型レベルで強制されない。

### 8.5 W003 コードの二重使用

ファイル存在チェック (checkPaths) と多重 implements (MultipleImplementsRule) が同じ W003 コードを使用。

---

## 9. Haskell / Rust 境界の曖昧さ

### 問題

「言語の中身の読み書きは Rust ツールが担う」方針だが:
- `Plat.Target.*` が CLAUDE.md に記載（Haskell 側でコード生成）
- 同じ「コード生成」が両側に分散し、権威が不明
- manifest が境界プロトコルだが、`Architecture` の劣化コピー（TypeExpr → 文字列で情報損失）

---

## 10. 総括

### 強み

- 手動 State モナド、phantom tag、meta DSL の三位一体は理論的に筋が通っている
- コードは読みやすく、意図が明確で、不必要な抽象化を避けている
- ドメイン知識の蓄積が深く、理論的基盤がしっかりしている

### 構造的問題（優先度順）

1. **想定ユーザーの不在** — 誰がなぜ plat を使うのかの物語が欠けている
2. **拡張の空洞化** — 語彙があってルールがない拡張は検証ツールとしての信頼性を損なう
3. **型安全性の二重基準** — DeclItem は型安全、meta は文字列ワイルドウェスト
4. **代数の名前負け** — merge/project が代数的性質を十分に保証していない
5. **テストの構造的不足** — プロパティベーステストの不在
6. **技術的負債** — renderTE 重複、hasCycle の潜在バグ、計算量問題
7. **未実装モジュールの散在** — spec/docs に書かれて実装がないものが複数

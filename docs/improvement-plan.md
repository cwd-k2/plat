# plat 改善方針

**日付**: 2026-03-07
**前提**: [critical-review.md](critical-review.md) の全指摘事項
**原則**: 既存の強み（手動 State モナド、phantom tag、meta DSL の三位一体）を壊さずに、構造的弱点を解消する

---

## 方針の骨格

レビューの指摘を3つの軸に整理し、それぞれの改善方向を定める。

| 軸 | 問題の本質 | 改善方向 |
|---|---|---|
| **Identity** | plat が誰のための何であるかが曖昧 | 自己定位の明確化と差別化要因の強化 |
| **Integrity** | 型安全性の主張と実態の乖離 | 技術的負債の解消と性質の保証強化 |
| **Value** | 拡張が語彙だけで意味論を持たない | 検証ルールの充実と実用的プリセットの提供 |

---

## Phase 0: 技術的負債の解消（即座に着手可能）

レビューで指摘された、設計判断を要しない技術的問題の修正。

### 0.1 renderTE の重複排除

`Plat.Verify.Manifest.renderTE` を削除し、`Plat.Core.TypeExpr.renderTypeExpr` を使用する。

**理由**: 完全同一のロジックが2箇所にある。manifest モジュールは既に `Plat.Core.Types` を import しているので、TypeExpr のインポート追加は自然。

### 0.2 hasCycle の修正

現在の `hasCycle` は `dfs` 関数が `visited` 集合を戻り値として返さないため、同一ノードが複数回探索される可能性がある。正しいトポロジカルソートに書き換える。

```haskell
hasCycle :: [LayerDef] -> Bool
hasCycle layers = any (\n -> dfs Set.empty n == Nothing) (map layerName layers)
  where
    depMap = Map.fromList [(layerName l, layerDeps l) | l <- layers]
    -- Nothing = cycle detected
    dfs :: Set Text -> Text -> Maybe (Set Text)
    dfs visiting n
      | n `Set.member` visiting = Nothing  -- cycle
      | otherwise = foldM dfs (Set.insert n visiting)
                          (Map.findWithDefault [] n depMap)
```

**理由**: コメントで潜在バグを認めている箇所を放置すべきでない。

### 0.3 W003 コードの分離

ファイル存在チェックと多重 implements が同じ W003 を使用している。多重 implements を独自コード（W004 等）に分離する。

**理由**: 同一コードで異なる問題を報告すると、ユーザーが原因を特定できない。

### 0.4 Mermaid sanitize の改善

スペースとハイフン以外の特殊文字（括弧、ドット、スラッシュ、アスタリスク等）にも対応する。

---

## Phase 1: Integrity — 技術的基盤の強化

### 1.1 プロパティベーステストの導入

**目的**: 代数的性質を具体例ではなく性質として検証する。

**対象**:
- `merge` の結合律（衝突なし時）、冪等性、右単位元
- `project` の冪等性
- `diff` の対称性（added/removed の対応）
- `relations` の完全性（DeclItem 由来の関係が漏れなく抽出されるか）

**手段**: QuickCheck を導入し、`Architecture` の `Arbitrary` インスタンスを定義する。テストハーネスは自前のまま維持してもよいが、プロパティベーステストだけは QuickCheck に委ねる。

**検討事項**: QuickCheck の導入は `base + text + containers` の制約を破る。テスト専用依存として受け入れるか、あるいは独自の shrink なし簡易プロパティテストを実装するか。plat の mtl 非依存ポリシーとの一貫性を考えると、後者も選択肢。

### 1.2 merge の安全性向上

3つの選択肢がある:

**A. merge を partial にする（推奨）**

```haskell
merge :: Text -> Architecture -> Architecture -> Either [Conflict] Architecture
```

`isCompatible` の結果を merge に埋め込み、不整合時は明示的に失敗させる。

利点: 暗黙的な情報損失が消える。ユーザーは衝突に対処を強制される。
欠点: 既存の `merge` の呼び出しサイトが壊れる。`mergeAll` も `Either` チェーンになる。

**B. 安全な merge と非安全な merge を分離**

```haskell
merge      :: Text -> Architecture -> Architecture -> Either [Conflict] Architecture
mergeForce :: Text -> Architecture -> Architecture -> Architecture  -- 左優先、現行動作
```

利点: 後方互換性維持。
欠点: `mergeForce` の存在がエスケープハッチの乱用を招く。

**C. 現状維持 + ドキュメント強化**

merge の「左優先上書き」動作を仕様として明記し、`isCompatible` の使用を強く推奨する。

利点: 破壊的変更なし。
欠点: 問題を先送りしているだけ。

### 1.3 project の Relation フィルタリング改善

現在は `relSource` or `relTarget` が残っていれば Relation を保持する。これを **both** に変更する:

```haskell
relOk r = relSource r `Set.member` names && relTarget r `Set.member` names
```

片端だけ残る壊れた Relation を除去する。

加えて、Constraint の射影時の扱いを検討する。`project` 後の Architecture に対して制約の `acCheck` が呼ばれたとき、除去された宣言に依存する制約は偽陽性を生む。選択肢:
- Constraint も除去する（過激だが安全）
- 射影後に check した結果を信頼しないようドキュメントで注意する

### 1.4 計算量の改善

`relations` の結果をキャッシュする仕組みを検討する。ただし `Architecture` は不変値なので、関数呼び出しごとの再計算は Haskell のレイジー評価で部分的に軽減される。

現実的な改善: `transitive` / `reachable` で使う関係を `Map Text [Relation]` に前処理してからグラフ走査する。

```haskell
transitive :: [Text] -> Text -> Architecture -> Set.Set Text
transitive kinds start a = go Set.empty [start]
  where
    adjMap = Map.fromListWith (++)
      [ (relSource r, [relTarget r])
      | r <- relations a, relKind r `elem` kinds
      ]
    go visited [] = visited
    go visited (x:xs)
      | x `Set.member` visited = go visited xs
      | otherwise = go (Set.insert x visited)
                       (Map.findWithDefault [] x adjMap ++ xs)
```

---

## Phase 2: Value — 拡張ルールの充実

### 2.1 拡張ルールの具体的な追加候補

各拡張に最低限の意味論的検証を追加する。

#### CQRS

```
CQRS-V001: query は write 系 boundary を needs してはならない
```

「write 系 boundary」の判定は、そのアーキテクチャが CQRS 拡張を使っている場合に command のみが needs する boundary を「write 系」と推論する。あるいは、boundary 側にも `readPort` / `writePort` の meta タグを導入する。

#### Events

```
EVT-V001: emit されたイベントに on_ ハンドラが存在すること
EVT-W001: on_ ハンドラの対象イベントが emit されていないこと（dead handler）
```

#### Modules

```
MOD-V001: expose されていない宣言が他モジュールから import されていないこと
MOD-V002: import のソースモジュールが存在すること
```

#### CleanArch

```
CA-V001: entity は enterprise レイヤーに存在すること
CA-V002: port は interface レイヤーに存在すること
CA-V003: impl は framework レイヤーに存在し、implements を持つこと
```

#### Http

```
HTTP-W001: controller に route が1つも定義されていないこと
```

### 2.2 推奨制約プリセットの提供

`constrain` で書けるが多くのユーザーが必要とする制約を、プリセットとして提供する。

```haskell
module Plat.Check.Presets where

-- | operation は少なくとも1つの boundary を needs すべき
operationNeedsBoundary :: Architecture -> [Text]

-- | Compose で bind されていない boundary が needs されている場合に警告
unwiredBoundaries :: Architecture -> [Text]

-- | needs の推移閉包にサイクルがないこと
noNeedsCycle :: Architecture -> [Text]
```

ユーザーは必要に応じて `constrain` に渡す:

```haskell
constrain "wiring-complete" "all needed boundaries must be wired" unwiredBoundaries
```

### 2.3 ルール追加の判断基準

闇雲にルールを増やすと「正しいアーキテクチャの矯正」になりかねない。追加の判断基準:

1. **パターン非依存か**: 特定のアーキテクチャパターンに依存しない普遍的な構造的性質か
2. **偽陽性のリスク**: 正当なアーキテクチャが誤って拒否される可能性はないか
3. **検出価値**: この違反が実務で実際に問題を引き起こすか

コアルール (V/W) はパターン非依存なもののみ。パターン依存のルールは拡張ルール (EXT-V/W) として提供し、ユーザーが選択的に `checkWith` に渡す。

---

## Phase 3: Identity — 自己定位の明確化

### 3.1 plat の差別化要因の再定義

Structurizr / C4 との差別化は「Haskell の型安全性」ではなく、以下の3つ:

1. **検証可能性**: `check` + `constrain` + 拡張ルールにより、アーキテクチャの構造的性質を宣言的に検証できる。C4 / Structurizr にはこの機能がない
2. **代数的操作**: `merge` / `project` / `diff` により、アーキテクチャを値として合成・射影・比較できる。これはプログラマブルなアーキテクチャ記述の本質
3. **実装との適合検証**: manifest → plat-verify により、記述と実装の乖離を自動検出できる。これは ADL が歴史的に達成できなかった「ライフサイクルへの統合」

### 3.2 ユーザーストーリーの明確化

plat の想定ユーザーと利用シーン:

**Primary**: チーム内のアーキテクチャオーナー（Haskell の基礎知識がある）が、プロジェクトのアーキテクチャを plat で記述し、CI で `check` と `plat-verify` を実行する。

**Secondary**: 開発者が生成された Markdown / Mermaid を参照してアーキテクチャを理解する。plat 自体は書かない。

**Tertiary**: マイクロサービス群の統合管理者が、各サービスの Architecture を `merge` して全体のビューを構築する。

この物語に合わせて README / docs を再構成する。

### 3.3 Perry & Wolf の Rationale への対応

Architecture にアーキテクチャ決定記録 (ADR) を紐付ける仕組みを検討する。

軽量な選択肢: `archMeta` に ADR への参照を記録する:

```haskell
arch "order-service" $ do
  meta "adr" "docs/adr/001-hexagonal.md"
  meta "adr" "docs/adr/002-cqrs-for-orders.md"
```

より構造的な選択肢: `Rationale` 型を導入し、設計判断の根拠を宣言レベルで記録する。ただし、これは plat の核心的価値（構造検証）からは離れるため、優先度は低い。

### 3.4 ext / customType の整理

以下のいずれかで対処する:

**A. TypeExpr を拡張する（推奨）**

```haskell
data TypeExpr
  = TBuiltin  Builtin
  | TRef      Text
  | TGeneric  Text [TypeExpr]
  | TNullable TypeExpr
  | TExt      Text          -- 新規: 外部型を明示的に区別
```

`ext` は `TExt` を返し、`customType` は `TRef` を返す。W002 で `TExt` を除外すれば、`Inject` 内かどうかに関係なく外部型を正しく扱える。

利点: 型レベルで ext と customType が区別される。
欠点: TypeExpr のコンストラクタ追加は下流の全パターンマッチに影響。manifest の renderTE にも変更が必要。

**B. ドキュメントで明確化し、現状維持**

`ext` と `customType` の意味的差異を docs に記述し、実装は `TRef` のまま。

---

## Phase 4: 未実装モジュールの整理

### 4.1 spec/docs と実装の乖離を解消

| 記載場所 | 記載内容 | 実態 | 対処 |
|----------|---------|------|------|
| spec-v0.6 | `Plat.Generate.Plat` | 未実装 | spec から削除するか実装する |
| roadmap | `Plat.Target.*` | Rust 移行済み・削除済み | roadmap を更新（完了済みに移動）|
| roadmap | `Plat.Verify.DepRules` | Rust 移行済み | 同上 |

`tooling-direction.md` には「`Plat.Target.*` および `Plat.Verify.DepRules` は Rust ツール群に移行済み。削除された。」と記載済み。roadmap の記述がこれと整合していない。

### 4.2 Plat.Generate.Plat の方針決定

`.plat` テキストフォーマットの生成器。選択肢:

- **実装する**: manifest JSON とは別に、人間可読なテキスト出力として価値がある
- **廃止する**: manifest JSON が Rust ツール群との標準境界であり、`.plat` テキストは冗長

manifest JSON を正式な唯一の出力フォーマットとし、`.plat` テキストは廃止するのが妥当。Haskell 側の責務は Architecture の構築・検証・manifest 生成に集中すべき。

---

## 実行順序

```
Phase 0 (即座)
  0.1 renderTE 重複排除
  0.2 hasCycle 修正
  0.3 W003 コード分離
  0.4 Mermaid sanitize 改善

Phase 1 (基盤)
  1.3 project の Relation フィルタリング修正
  1.4 transitive/reachable の計算量改善
  1.2 merge の安全性 → まず選択肢 B (安全版追加) → 後で A に移行
  1.1 プロパティベーステスト → Phase 1.2 と並行して Architecture の Arbitrary を設計

Phase 2 (価値)
  2.1 拡張ルール追加 → CleanArch, Events, Modules を優先（CQRS は write/read の判定が複雑）
  2.2 推奨制約プリセット
  2.3 ルール追加のガイドライン文書化

Phase 3 (方向性)
  3.1 差別化要因の README 反映
  3.2 ユーザーストーリーの明確化
  3.3 ADR 連携の検討（軽量な meta ベース）
  3.4 ext / customType の整理 → TExt 導入を含め、TypeExpr の拡張として Phase 1 と統合検討

Phase 4 (整理)
  4.1 spec/docs の整合性回復
  4.2 .plat フォーマットの方針決定
```

Phase 0 と Phase 1.3/1.4 は独立しており並行可能。Phase 2 は Phase 0 完了後に着手。Phase 3 はいつでも開始可能だが、Phase 2 の拡張ルール充実が「差別化要因の強化」の実体を伴うため、Phase 2 と並行が望ましい。

---

## 方針を貫く原則

1. **差別化要因に注力する**: 検証 (`check` + 拡張ルール) と代数 (`merge`/`project`) が plat の存在意義。ここを最も厚くする
2. **壊さない**: phantom tag + 手動 State モナド + meta DSL の三位一体は維持する。改善は延長線上で行う
3. **ユーザーの視点で判断する**: 「plat を書かない開発者にとっても価値がある」状態を目指す（生成物の質、CI 統合の容易さ）
4. **未実装を放置しない**: spec/docs に書いて実装しないのは負債。書いたなら実装するか、書いたものを消す

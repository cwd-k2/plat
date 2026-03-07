# 制約システム

`ArchConstraint` によるアーキテクチャレベルの不変条件。`constrain` で登録し、`check` / `checkWith` が自動評価する。

## 概要

```haskell
data ArchConstraint = ArchConstraint
  { acName  :: Text                      -- 制約名 (C:{name} として報告)
  , acDesc  :: Text                      -- 人間向け説明
  , acCheck :: Architecture -> [Text]    -- 違反時にメッセージ、準拠時に []
  }
```

`acCheck` は `[Text]` を返す (`[Diagnostic]` ではない)。循環依存を避けるため。`checkWith` が `[Text]` を `Diagnostic Error ("C:" <> acName)` に変換する。

## constrain コンビネータ

```haskell
constrain :: Text -> Text -> (Architecture -> [Text]) -> ArchBuilder ()
```

```haskell
architecture = arch "order-service" $ do
  useLayers [core, application, interface, infra]

  constrain "all-models-have-fields"
    "Every model must have at least one field"
    (require Model "model has no fields"
      (\d -> not (null [() | Field _ _ <- declBody d])))

  constrain "no-god-boundary"
    "No boundary should have more than 10 operations"
    (forAll Boundary $ \d ->
      let ops = [() | Op {} <- declBody d]
      in if length ops > 10
         then ["boundary " <> declName d <> " has too many ops"]
         else [])

  declare order
  ...
```

## 述語コンビネータ (`Plat.Core.Constraint`)

```haskell
require :: DeclKind -> Text -> (Declaration -> Bool) -> Architecture -> [Text]
forbid  :: DeclKind -> Text -> (Declaration -> Bool) -> Architecture -> [Text]
forAll  :: DeclKind -> (Declaration -> [Text]) -> Architecture -> [Text]
holds   :: Text -> (Architecture -> Bool) -> Architecture -> [Text]
```

| コンビネータ | 用途 |
|-------------|------|
| `require` | 指定種の**全**宣言が述語を満たすこと |
| `forbid` | 指定種の**いかなる**宣言も述語を満たさないこと |
| `forAll` | 汎用 — 各宣言に f を適用し違反メッセージを集約 |
| `holds` | アーキテクチャ全体の性質を検査 |

`require` と `forbid` は `forAll` の特殊化。

## 制約合成コンビネータ

```haskell
both  :: (Architecture -> [Text]) -> (Architecture -> [Text]) -> Architecture -> [Text]
allOf :: [Architecture -> [Text]] -> Architecture -> [Text]
oneOf :: [Architecture -> [Text]] -> Architecture -> [Text]
neg   :: (Architecture -> [Text]) -> Text -> Architecture -> [Text]
```

## プリセット制約 (`Plat.Check.Presets`)

よく使われる制約パターンを事前定義。`constrain` のチェック関数として直接使用可能。

```haskell
operationNeedsBoundary :: Architecture -> [Text]
-- 全 Operation が少なくとも1つの Boundary を needs していること

unwiredBoundaries :: Architecture -> [Text]
-- Compose 内で bind されていない Boundary がないこと

noNeedsCycle :: Architecture -> [Text]
-- needs 関係グラフに循環がないこと
```

```haskell
architecture = arch "my-service" $ do
  useLayers [core, application, interface, infra]

  constrain "ops-need-boundary"
    "every operation needs at least one boundary"
    operationNeedsBoundary

  constrain "all-wired"
    "every boundary should be wired"
    unwiredBoundaries

  constrain "no-cycle"
    "needs graph must be acyclic"
    noNeedsCycle

  declare order
  ...
```

## Manifest との関係

`ArchConstraint` の `acCheck` は関数フィールドのため直列化できない。manifest には `acName` と `acDesc` のみが出力される。

# Architecture 代数

`Plat.Core.Algebra` が提供する代数的操作。マイクロサービス分割の検討、レイヤー単位のレビュー、バージョン間の差分検出に使用する。

## 合成 (merge)

```haskell
merge    :: Text -> Architecture -> Architecture -> Either [Conflict] Architecture
mergeAll :: Text -> [Architecture] -> Either [Conflict] Architecture
```

`merge` は互換性チェックを行い、コンフリクトがあれば `Left [Conflict]` を返す。

### コンフリクト検出

```haskell
data Conflict = Conflict
  { conflictDecl :: Text
  , conflictDesc :: Text
  }

isCompatible :: Architecture -> Architecture -> [Conflict]
```

以下の場合にコンフリクトとなる:
- 同名宣言の **kind が異なる** ("kind mismatch")
- 同名宣言の **layer が異なる** ("layer mismatch")
- 同名レイヤーの **依存関係が異なる** ("layer dependency mismatch")

### 合成の意味論

コンフリクトがなければ、以下のフィールドを結合する:
- `archDecls`: 名前ベースで左優先 (nubBy)
- `archLayers`: 名前ベースで左優先
- `archTypes`: 名前ベースで左優先
- `archCustomTypes`: 重複排除
- `archConstraints`: 名前ベースで左優先
- `archRelations`: 重複排除
- `archMeta`: 連結

### 代数的性質

テストで検証済み:
- **結合律**: `merge (merge A B) C ≡ merge A (merge B C)` (宣言名と集合構造が一致)
- **冪等性**: `merge A A ≡ A` (構造的)
- **単位元**: `merge A empty ≡ A`
- **`mergeAll ≡ foldl merge`**

```haskell
fullSystem = mergeAll "full-system" [orderService, userService, paymentService]
```

## 射影 (project)

```haskell
project      :: (Declaration -> Bool) -> Architecture -> Architecture
projectLayer :: Text -> Architecture -> Architecture
projectKind  :: DeclKind -> Architecture -> Architecture
```

`project` は宣言をフィルタした後、残った宣言名に関連しない `archRelations` も除去する。

射影の冪等性: `project p (project p a) ≡ project p a`

```haskell
domainView = projectLayer "domain" architecture
boundaries = projectKind Boundary architecture
```

## 差分 (diff)

```haskell
data DeclChange
  = Added    Declaration              -- 新規追加
  | Removed  Declaration              -- 削除
  | Modified Declaration Declaration  -- 変更 (旧, 新)

data ArchDiff = ArchDiff
  { diffDecls     :: [DeclChange]
  , diffLayers    :: ([LayerDef], [LayerDef])   -- (追加, 削除)
  , diffRelations :: ([Relation], [Relation])   -- (追加, 削除)
  }

diff :: Architecture -> Architecture -> ArchDiff
```

`diff` は宣言名をキーとして Added / Removed / Modified を判定する。

### 代数的性質

テストで検証済み:
- **対称性**: `diff A B` の Added 数 = `diff B A` の Removed 数
- **同一性**: `diff A A` は変更なし

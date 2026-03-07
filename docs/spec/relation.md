# 関係グラフ

宣言間の有向関係を統一グラフとして扱う。

## Relation 型

```haskell
data Relation = Relation
  { relKind   :: Text              -- 関係の種類
  , relSource :: Text              -- 起点宣言名
  , relTarget :: Text              -- 終点宣言名
  , relMeta   :: [(Text, Text)]    -- 補足メタデータ
  }
```

## 関係の起源

### 暗黙的関係 (DeclItem から自動抽出)

| DeclItem | relKind | relSource | relTarget |
|----------|---------|-----------|-----------|
| `Needs name` | `"needs"` | 宣言名 | name |
| `Implements name` | `"implements"` | 宣言名 | name |
| `Bind bnd adp` | `"bind"` | bnd | adp |
| `Entry name` | `"entry"` | 宣言名 | name |
| `Field _ (TRef name)` | `"references"` | 宣言名 | name |
| `Input _ (TRef name)` | `"references"` | 宣言名 | name |
| `Output _ (TRef name)` | `"references"` | 宣言名 | name |

`TExt` は `typeRefs` から除外されるため、`Inject _ (TExt _)` は references 関係を生成しない。`TRef` は `TGeneric` や `TNullable` の内部にもネストしうるため、`typeRefs :: TypeExpr -> [Text]` で再帰的に抽出する。

### 明示的関係 (relate で登録)

```haskell
relate :: Text -> Decl a -> Decl b -> ArchBuilder ()
```

```haskell
relate "uses" getOrder placeOrder
relate "publishes" placeOrder order
```

## クエリ関数

```haskell
relations   :: Architecture -> [Relation]          -- 暗黙 + 明示の統一グラフ
relationsOf :: Text -> Architecture -> [Relation]  -- ソースでフィルタ

dependsOn     :: Text -> Architecture -> [Text]    -- "needs" の対象
implementedBy :: Text -> Architecture -> [Text]    -- "implements" の逆方向
boundTo       :: Text -> Architecture -> [Text]    -- "bind" の対象
```

## グラフ走査

```haskell
transitive :: [Text] -> Text -> Architecture -> Set Text
-- 指定した関係種に沿った推移閉包

reachable :: Text -> Architecture -> Set Text
-- 全関係種に沿った到達可能ノード

isAcyclic :: [Text] -> Architecture -> Bool
-- 指定した関係種のグラフに循環がないか

typeRefs :: TypeExpr -> [Text]
-- TypeExpr から TRef 名を再帰的に抽出 (TExt は除外)
```

```haskell
-- PlaceOrder から "needs" を辿って到達可能な全宣言
transitive ["needs"] "PlaceOrder" architecture
-- → Set.fromList ["OrderRepository", "PaymentGateway"]

-- needs グラフに循環がないことを検査
isAcyclic ["needs"] architecture
-- → True
```

## Manifest との関係

明示的関係 (`archRelations`) のみが JSON manifest に出力される。暗黙的関係は manifest の `declarations` から再構築可能。

```json
{
  "relations": [
    { "kind": "uses", "source": "GetOrder", "target": "PlaceOrder", "meta": {} }
  ]
}
```

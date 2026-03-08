# 型式システム

`TypeExpr` による型の表現と、型参照の仕組み。

## ビルトイン型

```haskell
string   :: TypeExpr    -- String
int      :: TypeExpr    -- Int
float    :: TypeExpr    -- Float
decimal  :: TypeExpr    -- Decimal
bool     :: TypeExpr    -- Bool
unit     :: TypeExpr    -- Unit
bytes    :: TypeExpr    -- Bytes
dateTime :: TypeExpr    -- DateTime
any_     :: TypeExpr    -- Any
```

## ジェネリック型コンストラクタ

```haskell
result   :: TypeExpr -> TypeExpr -> TypeExpr  -- Result<T, E>
option   :: TypeExpr -> TypeExpr              -- Option<T>
list     :: TypeExpr -> TypeExpr              -- List<T>
set      :: TypeExpr -> TypeExpr              -- Set<T>
map_  :: TypeExpr -> TypeExpr -> TypeExpr  -- Map<K, V>
stream   :: TypeExpr -> TypeExpr              -- Stream<T>
nullable :: TypeExpr -> TypeExpr              -- T?
```

## 参照

```haskell
ref    :: Referenceable k => Decl k -> TypeExpr   -- TRef を生成
idOf   :: Decl 'Model -> TypeExpr                 -- TGeneric "Id" [TRef name]
alias  :: TypeAlias -> TypeExpr                    -- TRef aliasName

class Referenceable (k :: DeclKind)
instance Referenceable 'Model
instance Referenceable 'Boundary
instance Referenceable 'Operation
-- Adapter, Compose への ref はコンパイルエラー
```

### 参照コンビネータ

頻出パターン `list (ref x)` を簡潔に書くためのショートハンド。

```haskell
listOf   :: Referenceable k => Decl k -> TypeExpr   -- list . ref
optionOf :: Referenceable k => Decl k -> TypeExpr   -- option . ref
setOf    :: Referenceable k => Decl k -> TypeExpr   -- set . ref
```

## 外部型とカスタム型

| 関数 | 生成する TypeExpr | W002 検証 | 用途 |
|------|-------------------|----------|------|
| `ext` | `TExt name` | 対象外 | ターゲット言語固有の型 (`*sql.DB` 等) |
| `customType` | `TRef name` | 対象 (`registerType` 必要) | プロジェクト定義の型 (`UUID` 等) |

```haskell
ext        :: Text -> TypeExpr   -- TExt を生成
customType :: Text -> TypeExpr   -- TRef を生成
```

**AST レベルの区別**: `ext` は `TExt` コンストラクタ、`customType`/`ref` は `TRef` コンストラクタを使用する。これにより W002 検証や `typeRefs` 関数で外部型を正確に除外できる。

## 予約型参照

以下の型名は plat が予約しており、`registerType` なしで使用でき、W002 の検証対象外。

| 予約名 | 生成元 | 用途 |
|--------|--------|------|
| `Error` | `error_` | 言語横断的なエラー概念 |
| `Id` | `idOf` | モデルの識別子型 |

```haskell
error_ :: TypeExpr   -- TRef "Error"
```

## 命名規約 — Haskell 予約語との衝突回避

Haskell の予約語や Prelude の名前と衝突する識別子には **trailing underscore** を付与する。

| plat 名 | 回避対象 | 用途 |
|----------|---------|------|
| `error_` | `Prelude.error` | Error 型参照 |
| `any_` | `Prelude.any` | Any ビルトイン型 |
| `assert_` | (拡張) | DbC アサーション |
| `import_` | `import` キーワード | Modules import |
| `on_` | `Data.Function.on` | Events ハンドラ |

衝突がない `enum`, `impl`, `apply` 等にはアンダースコアを付けない。

## 利用例

```haskell
field "name"      string                         -- ビルトイン
field "id"        (customType "UUID")            -- カスタム型 (registerType 必要)
field "status"    (ref orderStatus)              -- model 参照
field "items"     (listOf orderItem)             -- 参照コンビネータ
field "total"     (alias money)                  -- TypeAlias 参照
field "metadata"  (map_ string any_)          -- any_
field "parent"    (nullable (ref category))      -- nullable
inject "db"       (ext "*sql.DB")                -- 外部型 (TExt)
op "save" ["order" .: ref order] ["err" .: error_]  -- 予約型
```

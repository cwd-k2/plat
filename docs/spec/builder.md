# ビルダーモナド

宣言とアーキテクチャを構築するためのモナド。mtl に依存しない手動 State モナド。

## DeclWriter k

宣言の本体を構築するモナド。phantom type `k :: DeclKind` がコンビネータを制約する。

```haskell
newtype DeclWriter (k :: DeclKind) a = DeclWriter (DeclBuild -> (a, DeclBuild))
```

Functor / Applicative / Monad を手動実装。

### コンビネータ

```haskell
-- Model 専用
field :: Text -> TypeExpr -> DeclWriter 'Model ()

-- Boundary 専用
op  :: Text -> [Param] -> [Param] -> DeclWriter 'Boundary ()
op' :: Text -> [Param] -> TypeExpr -> DeclWriter 'Boundary ()  -- 単一返却

-- Operation 専用
input  :: Text -> TypeExpr -> DeclWriter 'Operation ()
output :: Text -> TypeExpr -> DeclWriter 'Operation ()
needs  :: Decl 'Boundary -> DeclWriter 'Operation ()

-- Adapter 専用
implements :: Decl 'Boundary -> DeclWriter 'Adapter ()  -- 最大1回
inject     :: Text -> TypeExpr -> DeclWriter 'Adapter ()

-- Compose 専用
bind      :: Decl 'Boundary -> Decl 'Adapter -> DeclWriter 'Compose ()
entry     :: Decl k -> DeclWriter 'Compose ()
entryName :: Text -> DeclWriter 'Compose ()  -- H2 の明示的例外

-- 全 DeclKind 共通
meta :: Text -> Text -> DeclWriter k ()

-- Compose 以外 (HasPath 制約)
path :: HasPath k => FilePath -> DeclWriter k ()
```

## スマートコンストラクタ

`DeclWriter k` を実行し、内部状態から `Decl k` を構築する。

```haskell
model     :: Text -> LayerDef -> DeclWriter 'Model ()     -> Decl 'Model
boundary  :: Text -> LayerDef -> DeclWriter 'Boundary ()  -> Decl 'Boundary
operation :: Text -> LayerDef -> DeclWriter 'Operation ()  -> Decl 'Operation
adapter   :: Text -> LayerDef -> DeclWriter 'Adapter ()   -> Decl 'Adapter
compose   :: Text -> DeclWriter 'Compose ()               -> Decl 'Compose
```

`compose` のみレイヤーを持たない (`declLayer = Nothing`)。レイヤー横断的な配線を記述するため。

## ArchBuilder

アーキテクチャ全体を構築するモナド。

```haskell
newtype ArchBuilder a = ArchBuilder (ArchBuild -> (a, ArchBuild))
```

### コンビネータ

```haskell
arch         :: Text -> ArchBuilder () -> Architecture
useLayers    :: [LayerDef] -> ArchBuilder ()
useTypes     :: [TypeAlias] -> ArchBuilder ()
registerType :: Text -> ArchBuilder ()
declare      :: Decl k -> ArchBuilder ()       -- phantom tag を消去して登録
declares     :: [Declaration] -> ArchBuilder () -- メタプログラミング用
constrain    :: Text -> Text -> (Architecture -> [Text]) -> ArchBuilder ()
relate       :: Text -> Decl a -> Decl b -> ArchBuilder ()
```

## レイヤー定義

```haskell
layer   :: Text -> LayerDef
depends :: LayerDef -> [LayerDef] -> LayerDef
```

```haskell
core        = layer "core"
application = layer "application" `depends` [core]
interface   = layer "interface"   `depends` [core]
infra       = layer "infra"       `depends` [core, application, interface]
```

## 型エイリアス

```haskell
(=:)  :: Text -> TypeExpr -> TypeAlias
alias :: TypeAlias -> TypeExpr

money = "Money" =: decimal
```

## implements の多重度

adapter 内で最大 1 回。複数回呼び出した場合、最後の値が採用される (W003 警告)。`implements` を含まない adapter も有効 (HTTP ハンドラ等)。

## 型安全性の範囲

**コンパイル時に検出**:
- 未定義の宣言への参照 (変数未定義)
- `needs` に model/adapter を指定 (`Decl 'Boundary` 不一致)
- `bind` の引数種の取り違え
- `ref` に adapter/compose を指定 (`Referenceable` 制約不一致)
- model 内で op/inject を使用 (`DeclWriter` の phantom 不一致)

**`check` による実行時検証**:
- レイヤー依存関係の違反 (V001)
- 同名宣言の重複 (V009)
- adapter が boundary の op を充足しているか (V007)

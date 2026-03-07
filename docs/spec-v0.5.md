# plat-hs 仕様書

**バージョン**: 0.5.0-draft  
**ステータス**: RFC  
**最終更新**: 2026-03-06  
**前提**: Plat 仕様 v0.5.0-draft  
**リポジトリ名**: `plat-hs`

### v0.4 → v0.5 変更概要

- §1.1 に**ねらい**（設計・アーキテクチャの抽出に専念）を追記
- `implements` を中置演算子から **DeclWriter 内コンビネータ**に変更（adapter の構文統一）
- AST の `KAdapter` から `Maybe Text` を除去し、`Implements` を `DeclItem` に移動

---

## 目次

1. [概要と位置づけ](#1-概要と位置づけ)
2. [設計方針](#2-設計方針)
3. [アーキテクチャ](#3-アーキテクチャ)
4. [Core eDSL — 参照モデル](#4-core-edsl--参照モデル)
5. [Core eDSL — AST](#5-core-edsl--ast)
6. [Core eDSL — 宣言構文](#6-core-edsl--宣言構文)
7. [型式システム](#7-型式システム)
8. [検証システム](#8-検証システム)
9. [パッケージ拡張システム](#9-パッケージ拡張システム)
10. [標準拡張パッケージ](#10-標準拡張パッケージ)
11. [.plat 生成バックエンド](#11-plat-生成バックエンド)
12. [パッケージ構成と利用](#12-パッケージ構成と利用)
13. [GHC 要件](#13-ghc-要件)
14. [利用例 — Go クリーンアーキテクチャ](#14-利用例--go-クリーンアーキテクチャ)
15. [利用例 — メタプログラミング](#15-利用例--メタプログラミング)
16. [将来構想](#16-将来構想)

---

## 1. 概要と位置づけ

### 1.1 plat-hs とは

plat-hs は Plat（アーキテクチャ設計支援ツール）の **Haskell eDSL 実装**である。

**ねらい**: ソフトウェアの設計を議論するとき、言語の構文、ディレクトリ構造、フレームワークの作法、DI コンテナの設定など、実装上の関心事に議論が引きずられることが多い。plat-hs は、これらの実装詳細から**設計・アーキテクチャだけを抽出**し、「何がどのレイヤーにあり、何が何に依存しているか」という構造の検討に専念できる環境を提供することを目指す。Go で書くか TypeScript で書くか、gin を使うか chi を使うかに関わらず、設計の骨格は同じ eDSL で記述・検証できる。

`.plat` ファイルの記法を Haskell の値参照と do 記法で表現し、以下を提供する。

- **設計記述**: model / boundary / operation 等を Haskell の値として記述する
- **参照安全性**: 宣言間の参照を変数束縛で表現し、typo をコンパイルエラーにする
- **検証**: `plat check` 相当のルール検証を Haskell プログラムとして実行する
- **メタプログラミング**: CRUD 一括生成等、Haskell の関数で設計を操作する
- **.plat 生成**: eDSL から `.plat` テキストを生成し、Rust ツールチェーンと連携する

### 1.2 Plat エコシステムにおける位置づけ

```
                        ┌─────────────────────┐
                        │   plat-hs (Haskell)  │
                        │   eDSL で設計を記述   │
                        └──────────┬──────────┘
                                   │
                    ┌──────────────┼──────────────┐
                    │              │              │
                    ▼              ▼              ▼
                検証           .plat 生成     メタプログラミング
           (plat check)      (テキスト出力)   (一括生成・比較等)
                                   │
                                   ▼
                     ┌─────────────────────┐
                     │  Rust ツールチェーン   │
                     │  (将来: plat CLI)     │
                     │  sync / generate 等   │
                     └─────────────────────┘
```

### 1.3 なぜ Haskell か

| 要件 | Haskell の対応 |
|------|---------------|
| 宣言間の参照安全性 | 変数束縛がそのまま参照グラフになる |
| 宣言的な設計記述 | do 記法 |
| 検証ルールの合成・拡張 | 型クラス + 代数的データ型 |
| パッケージ拡張 | Haskell モジュール + 型クラスインスタンス |
| メタプログラミング | 通常の関数・リスト操作 |

---

## 2. 設計方針

**H1 — Plat 仕様への忠実性**  
Plat v0.5 の Core 仕様を完全に表現する。Haskell 固有の追加は Plat の方針（P1〜P6）と矛盾しない範囲に限る。

**H2 — 値による参照**  
宣言間の参照はすべて Haskell の変数束縛で表現し、文字列参照を排除する。

**H3 — 宣言は均質な値**  
すべての宣言が同じ `Declaration` 型であり、リスト・関数で自然に操作できる。

**H4 — 名前は宣言に属し、参照は値に属す**  
.plat に出力される識別子だけが文字列。他の宣言からの参照はすべて値経由。

**H5 — 型も値**  
ビルトイン型・model 参照・カスタム型をすべて `TypeExpr` の値として提供する。

**H6 — 生成物としての .plat**  
生成された `.plat` は手書きと区別がつかない正規ファイル。

**H7 — 柔軟な構造パターン** *(v0.4 追加)*  
adapter は boundary を implements するものだけでなく、HTTP ハンドラ・CLI・gRPC server 等の入口コンポーネントも表現できる。実プロジェクトの多様な構造に対応する。

---

## 3. アーキテクチャ

### 3.1 モジュール構成

```
plat-hs/
├── Plat/
│   ├── Core.hs                -- 公開 API の再エクスポート
│   ├── Core/
│   │   ├── Types.hs           -- AST 定義
│   │   ├── Builder.hs         -- do 記法ビルダー
│   │   └── TypeExpr.hs        -- 型式: ビルトイン + コンストラクタ
│   ├── Check.hs               -- 検証エンジン
│   ├── Check/
│   │   ├── Rules.hs           -- Core 検証ルール
│   │   └── Class.hs           -- PlatRule 型クラス（拡張ポイント）
│   ├── Generate.hs            -- 生成エンジン（再エクスポート）
│   └── Generate/
│       ├── Plat.hs            -- .plat フォーマッタ
│       ├── Mermaid.hs         -- Mermaid 図
│       └── Markdown.hs        -- Markdown ドキュメント
```

### 3.2 データフロー

```
ユーザーの .hs
    │  import Plat.Core
    ▼
eDSL 式（値参照 + do 記法）
    │
    ▼
Architecture（AST）
    │
    ├──→ check / checkWith ──→ CheckResult
    ├──→ renderFiles       ──→ [(FilePath, Text)]  (.plat)
    ├──→ renderMermaid     ──→ Text
    └──→ renderMarkdown    ──→ Text
```

---

## 4. Core eDSL — 参照モデル

### 4.1 文字列と値の役割分担

| 用途 | 手段 | 例 |
|------|------|-----|
| **命名** | 文字列 | `model "Order"`, `op "save"` |
| **レイヤー参照** | `LayerDef` 値 | `model "Order" core` |
| **宣言間参照** | `Declaration` 値 | `needs orderRepo`, `bind orderRepo pgRepo` |
| **型参照** | `TypeExpr` 値 | `field "total" decimal`, `ref order` |

文字列が残るのは**命名**（.plat 出力用の識別子）と**パス**（`path "src/..."` のファイルパス）のみ。

### 4.2 参照の解決

eDSL の値参照は、AST 構築時に名前文字列に解決される。AST は文字列ベースであり `.plat` と 1:1 対応を保つ。

```
eDSL                              AST
needs orderRepo            →    Needs "OrderRepository"
field "total" decimal      →    Field "total" (TBuiltin BDecimal)
ref order                  →    TRef "Order"
```

---

## 5. Core eDSL — AST

### 5.1 `Plat.Core.Types`

```haskell
module Plat.Core.Types where

import Data.Text (Text)
import Data.Map.Strict (Map)

-- | アーキテクチャ全体
data Architecture = Architecture
  { archName        :: Text
  , archLayers      :: [LayerDef]
  , archTypes       :: [TypeAlias]
  , archCustomTypes :: [Text]           -- registerType で登録された型名
  , archDecls       :: [Declaration]
  , archMeta        :: Map Text Text
  } deriving (Show, Eq)

-- | レイヤー定義
data LayerDef = LayerDef
  { layerName :: Text
  , layerDeps :: [Text]
  } deriving (Show, Eq)

-- | 型エイリアス
data TypeAlias = TypeAlias
  { aliasName :: Text
  , aliasType :: TypeExpr
  } deriving (Show, Eq)

-- | 宣言
data Declaration = Declaration
  { declKind  :: DeclKind
  , declName  :: Text
  , declLayer :: Maybe Text
  , declPaths :: [FilePath]
  , declBody  :: [DeclItem]
  , declMeta  :: Map Text Text
  } deriving (Show, Eq)

-- | 宣言の種類
data DeclKind
  = KModel
  | KOperation
  | KBoundary
  | KAdapter
  | KCompose
  deriving (Show, Eq)

-- | 宣言内の要素
data DeclItem
  = Field      Text TypeExpr
  | Op         Text [Param] [Param]      -- 名前, 入力パラメータ, 出力パラメータ
  | Input      Text TypeExpr
  | Output     Text TypeExpr
  | Needs      Text
  | Implements Text                       -- boundary 名（adapter 内、省略可）
  | Inject     Text TypeExpr
  | Bind       Text Text
  | Entry      Text
  | Meta       Text Text
  deriving (Show, Eq)

-- | 名前付きパラメータ
data Param = Param
  { paramName :: Text
  , paramType :: TypeExpr
  } deriving (Show, Eq)

-- | 型式
data TypeExpr
  = TBuiltin  Builtin
  | TRef      Text
  | TGeneric  Text [TypeExpr]
  | TNullable TypeExpr
  deriving (Show, Eq)

-- | ビルトイン型
data Builtin
  = BString | BInt | BFloat | BDecimal
  | BBool | BUnit | BBytes | BDateTime
  | BAny
  deriving (Show, Eq, Enum, Bounded)
```

### 5.2 v0.3 からの AST 変更点

| 項目 | v0.3 | v0.5 | 理由 |
|------|------|------|------|
| `Op` | `Text [TypeExpr] TypeExpr` | `Text [Param] [Param]` | 名前付きパラメータ、多値返却対応 |
| `KAdapter` | `KAdapter { adapterImpl :: Text }` | `KAdapter`（引数なし） | implements を DeclItem に移動 |
| `DeclItem` | — | `Implements Text` 追加 | adapter 内コンビネータ化 |
| `Builtin` | 8 種 | 9 種（`BAny` 追加） | any/interface{} 対応 |
| `Architecture` | — | `archCustomTypes :: [Text]` 追加 | カスタム型登録 |

---

## 6. Core eDSL — 宣言構文

### 6.1 レイヤー定義

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

### 6.2 型エイリアス

```haskell
(=:) :: Text -> TypeExpr -> TypeAlias
alias :: TypeAlias -> TypeExpr
```

```haskell
money        = "Money"        =: decimal
emailAddress = "EmailAddress" =: string
orderItems   = "OrderItems"   =: list (ref orderItem)
```

### 6.3 モデル

```haskell
model :: Text -> LayerDef -> DeclWriter () -> Declaration
field :: Text -> TypeExpr -> DeclWriter ()
path  :: FilePath -> DeclWriter ()
```

```haskell
orderItem :: Declaration
orderItem = model "OrderItem" core $ do
  field "productId" uuid              -- カスタム型
  field "quantity"  int
  field "unitPrice" (ref money)       -- model 参照

order :: Declaration
order = model "Order" core $ do
  path "domain/order.go"
  field "id"         uuid
  field "customerId" uuid
  field "items"      (list (ref orderItem))
  field "status"     (ref orderStatus)
  field "total"      (ref money)
  field "createdAt"  dateTime
  field "updatedAt"  dateTime
```

### 6.4 バウンダリ — 名前付きシグネチャ

```haskell
boundary :: Text -> LayerDef -> DeclWriter () -> Declaration
op       :: Text -> [Param] -> [Param] -> DeclWriter ()

-- | Param ヘルパー（中置演算子）
(.:) :: Text -> TypeExpr -> Param
```

`(.:)` 演算子により、パラメータを `"name" .: type` で宣言する。

```haskell
orderRepo :: Declaration
orderRepo = boundary "OrderRepository" interface $ do
  path "usecase/port/order_repo.go"
  op "save"
    ["order" .: ref order]
    ["err"   .: error_]
  op "findById"
    ["id" .: uuid]
    ["order" .: ref order, "err" .: error_]
  op "findByCustomer"
    ["customerId" .: uuid]
    ["orders" .: stream (ref order)]

paymentGateway :: Declaration
paymentGateway = boundary "PaymentGateway" interface $ do
  path "usecase/port/payment.go"
  op "charge"
    ["amount" .: ref money, "cardToken" .: string]
    ["chargeId" .: string, "err" .: error_]

eventPublisher :: Declaration
eventPublisher = boundary "EventPublisher" interface $ do
  path "usecase/port/event_pub.go"
  op "publish"
    ["topic" .: string, "payload" .: any_]
    ["err" .: error_]
```

**設計判断**: `.plat` の boundary op は `save: (Order) -> Result<Unit, Error>` という positional な記法だが、plat-hs ではパラメータ名を保持する。.plat 生成時に名前を落としても、eDSL の可読性と将来の sync チェック精度が向上する。Go/TypeScript の名前付き引数の慣習にも合致する。

**単一返却のショートハンド**: 返却パラメータが 1 つで名前が不要な場合のヘルパー。

```haskell
-- | 単一返却のショートハンド
op' :: Text -> [Param] -> TypeExpr -> DeclWriter ()
op' name params retType = op name params ["_" .: retType]
```

```haskell
-- 可読性を優先して使い分け可能
op "findAll" [] ["orders" .: stream (ref order)]   -- 名前付き
op' "count"  [] int                                 -- ショートハンド
```

### 6.5 オペレーション

```haskell
operation :: Text -> LayerDef -> DeclWriter () -> Declaration
input     :: Text -> TypeExpr -> DeclWriter ()
output    :: Text -> TypeExpr -> DeclWriter ()
needs     :: Declaration -> DeclWriter ()
```

```haskell
placeOrder :: Declaration
placeOrder = operation "PlaceOrder" application $ do
  path "usecase/place_order.go"
  input  "customerId" uuid
  input  "items"      (list (ref orderItem))
  input  "cardToken"  string
  output "order"      (ref order)
  output "err"        error_
  needs orderRepo
  needs paymentGateway
  needs eventPublisher
```

`input` / `output` は名前付き。Go の構造体フィールドや関数の多値返却に自然に対応する。

**input に model 参照を使うパターン**: DTO/Command 構造体がドメインモデルと分離している場合。

```haskell
-- DTO を model として定義
placeOrderInput :: Declaration
placeOrderInput = model "PlaceOrderInput" application $ do
  field "customerId" uuid
  field "items"      (list (ref orderItem))
  field "cardToken"  string

-- operation で DTO を参照
placeOrder :: Declaration
placeOrder = operation "PlaceOrder" application $ do
  path "usecase/place_order.go"
  input  "cmd" (ref placeOrderInput)     -- DTO への値参照
  output "res" (result (ref order) error_)
  needs orderRepo
```

**どちらの書き方を選ぶかはプロジェクトの判断**。input を inline で列挙するか、model を分けて ref するか。eDSL はどちらも許容する。

### 6.6 アダプター

```haskell
adapter    :: Text -> LayerDef -> DeclWriter () -> Declaration
implements :: Declaration -> DeclWriter ()
inject     :: Text -> TypeExpr -> DeclWriter ()
```

`implements` は `DeclWriter` 内のコンビネータ。boundary の `Declaration` 値を受け取る。省略可。

```haskell
-- boundary を implements する adapter
postgresOrderRepo :: Declaration
postgresOrderRepo = adapter "PostgresOrderRepo" infra $ do
  implements orderRepo                        -- boundary を値参照
  path "adapter/postgres/order_repo.go"
  inject "db" (ext "*sql.DB")

stripePayment :: Declaration
stripePayment = adapter "StripePayment" infra $ do
  implements paymentGateway
  path "adapter/stripe/payment.go"
  inject "client" (ext "*stripe.Client")

-- implements なしの adapter（HTTP ハンドラ、CLI 等）
httpHandler :: Declaration
httpHandler = adapter "OrderHttpHandler" infra $ do
  path "adapter/http/handler.go"
  inject "placeOrder"  (ref placeOrder)
  inject "cancelOrder" (ref cancelOrder)
  inject "getOrder"    (ref getOrder)
  inject "router"      (ext "chi.Router")
```

adapter の構文は `implements` の有無に関わらず同じ `adapter name layer $ do ...` の形をとる。`implements` がある場合のみ V007（boundary の op 未宣言）の検証対象となる。レイヤー依存（V001）はどちらの場合も検証される。

**設計判断**: `implements` をビルダー内コンビネータにすることで、adapter の記述が完全に統一される。v0.4 の中置演算子 `` `implements` `` は括弧の位置が不自然だった（`adapter ... (do ...) \`implements\` repo`）。ビルダー内であれば `path`, `inject` と同列に読め、宣言の冒頭に置く慣習で boundary との関係が一目で分かる。

### 6.7 コンポーズ

```haskell
compose :: Text -> DeclWriter () -> Declaration
bind    :: Declaration -> Declaration -> DeclWriter ()
```

`entry` は `Declaration` 値と `Text` 値の両方を受け付ける。

```haskell
class IsEntry a where
  entry :: a -> DeclWriter ()

instance IsEntry Declaration where
  entry decl = tell [Entry (declName decl)]

instance IsEntry Text where
  entry name = tell [Entry name]
```

```haskell
appRoot :: Declaration
appRoot = compose "AppRoot" $ do
  bind orderRepo       postgresOrderRepo
  bind paymentGateway  stripePayment
  bind eventPublisher  kafkaPublisher
  entry httpHandler                  -- Declaration 値
  entry "GrpcServer"                 -- 文字列（Plat 宣言がない場合）
```

### 6.8 アーキテクチャ全体

```haskell
arch         :: Text -> ArchBuilder () -> Architecture
useLayers    :: [LayerDef] -> ArchBuilder ()
useTypes     :: [TypeAlias] -> ArchBuilder ()
registerType :: Text -> ArchBuilder ()       -- カスタム型の登録
declare      :: Declaration -> ArchBuilder ()
declares     :: [Declaration] -> ArchBuilder ()
```

```haskell
architecture :: Architecture
architecture = arch "order-service" $ do
  useLayers [core, application, interface, infra]
  useTypes  [money, emailAddress]
  registerType "UUID"
  declares [ orderStatus, orderItem, order
           , orderRepo, paymentGateway, eventPublisher
           , placeOrder, cancelOrder, getOrder
           , postgresOrderRepo, stripePayment, kafkaPublisher
           , httpHandler
           , appRoot
           ]
```

---

## 7. 型式システム

### 7.1 ビルトイン型（定数値）

```haskell
string   :: TypeExpr    -- String
int      :: TypeExpr    -- Int
float    :: TypeExpr    -- Float
decimal  :: TypeExpr    -- Decimal
bool     :: TypeExpr    -- Bool
unit     :: TypeExpr    -- Unit
bytes    :: TypeExpr    -- Bytes
dateTime :: TypeExpr    -- DateTime
any_     :: TypeExpr    -- Any（Go の any, TS の unknown 等）
```

### 7.2 ジェネリック型コンストラクタ

```haskell
result   :: TypeExpr -> TypeExpr -> TypeExpr  -- Result<T, E>
option   :: TypeExpr -> TypeExpr              -- Option<T>
list     :: TypeExpr -> TypeExpr              -- List<T>
set      :: TypeExpr -> TypeExpr              -- Set<T>
mapType  :: TypeExpr -> TypeExpr -> TypeExpr  -- Map<K, V>
stream   :: TypeExpr -> TypeExpr              -- Stream<T>
nullable :: TypeExpr -> TypeExpr              -- T?
```

### 7.3 参照

```haskell
ref      :: Declaration -> TypeExpr           -- model/宣言への型参照
idOf     :: Declaration -> TypeExpr           -- Id<T>
alias    :: TypeAlias -> TypeExpr             -- TypeAlias への参照
```

### 7.4 外部型とカスタム型

```haskell
-- | ターゲット言語固有の外部型（inject 用、W002 検証対象外）
ext :: Text -> TypeExpr

-- | プロジェクト定義のカスタム型（registerType で登録、W002 検証対象）
customType :: Text -> TypeExpr
```

**使い分け**:

| 関数 | 用途 | W002 検証 | 例 |
|------|------|----------|-----|
| `ext` | 言語固有の注入型（DB接続、外部ライブラリ） | 対象外 | `ext "*sql.DB"`, `ext "chi.Router"` |
| `customType` | ドメインで使うがビルトインにない型 | 対象 | `customType "UUID"`, `customType "URL"` |

`customType` で生成した `TypeExpr` を使うには、`arch` 内で `registerType` しておく必要がある。登録なしに使った場合、W002（未定義型）として報告される。

```haskell
uuid = customType "UUID"
url_ = customType "URL"

architecture = arch "my-app" $ do
  registerType "UUID"
  registerType "URL"
  ...
```

### 7.5 エラー型

Haskell の `error` との名前衝突を避けるため `error_` を提供する。

```haskell
error_ :: TypeExpr
error_ = TRef "Error"
```

### 7.6 利用例まとめ

```haskell
field "name"      string                         -- ビルトイン
field "age"       int                            -- ビルトイン
field "id"        uuid                           -- カスタム型
field "status"    (ref orderStatus)              -- model 参照
field "items"     (list (ref orderItem))         -- ジェネリクス + 参照
field "total"     (alias money)                  -- TypeAlias 参照
field "metadata"  (mapType string any_)          -- any_
field "parent"    (nullable (ref category))      -- nullable
inject "db"       (ext "*sql.DB")                -- 外部型

op "save"
  ["order" .: ref order]                         -- 名前付きパラメータ
  ["err" .: error_]
```

---

## 8. 検証システム

### 8.1 コンパイル時 vs 実行時

| 違反 | GHC コンパイル時 | check 実行時 |
|------|-----------------|-------------|
| 未定義レイヤー・宣言・boundary への参照 | ✓ 変数未定義 | — |
| needs / bind の参照先 typo | ✓ 変数未定義 | — |
| V001 レイヤー依存違反 | — | ✓ |
| V002 レイヤー循環依存 | — | ✓ |
| V003 needs に adapter 指定 | — | ✓ |
| V004 boundary に adapter 型 | — | ✓ |
| V005 compose 外での bind | — | ✓ |
| V006 パッケージキーワード衝突 | — | ✓ |
| V007 adapter が boundary の op を未宣言 | — | ✓（implements ありのみ） |
| V008 存在しない boundary への bind | ✓ 値参照 | — |
| W001 未解決の boundary | — | ✓ |
| W002 未定義型名 | — | ✓（ext 除外、customType は registerType 要） |
| W003 @path のファイル不在 | — | ✓（checkIO） |
| W004 boundary シグネチャ変更 | — | 将来 |

### 8.2 API

```haskell
module Plat.Check where

data CheckResult = CheckResult
  { violations :: [Diagnostic]
  , warnings   :: [Diagnostic]
  }

instance Semigroup CheckResult where ...
instance Monoid CheckResult where ...

data Diagnostic = Diagnostic
  { dSeverity :: Severity
  , dCode     :: Text
  , dMessage  :: Text
  , dSource   :: Text
  , dTarget   :: Maybe Text
  }

data Severity = Error | Warning

check       :: Architecture -> CheckResult           -- 純粋（W003 以外）
checkIO     :: Architecture -> IO CheckResult        -- W003 込み
checkWith   :: [SomeRule] -> Architecture -> CheckResult
prettyCheck :: CheckResult -> Text
checkOrFail :: Architecture -> IO ()

hasViolations :: CheckResult -> Bool
hasWarnings   :: CheckResult -> Bool
```

### 8.3 検証ルール型クラス

```haskell
module Plat.Check.Class where

class PlatRule a where
  ruleCode  :: a -> Text
  checkDecl :: a -> Architecture -> Declaration -> [Diagnostic]
  checkDecl _ _ _ = []
  checkArch :: a -> Architecture -> [Diagnostic]
  checkArch _ _ = []

data SomeRule where
  SomeRule :: PlatRule a => a -> SomeRule

coreRules :: [SomeRule]
```

### 8.4 V007 の条件付き適用

V007（adapter が boundary の op を未宣言）は `Implements` を含む adapter にのみ適用する。

```haskell
instance PlatRule AdapterCoverageRule where
  ruleCode _ = "V007"
  checkDecl _ arch decl = case declKind decl of
    KAdapter
      | Just bndName <- findImplements (declBody decl) -> ...  -- 検証
    _ -> []

-- | DeclItem リストから Implements を探す
findImplements :: [DeclItem] -> Maybe Text
findImplements items =
  listToMaybe [name | Implements name <- items]
```

---

## 9. パッケージ拡張システム

### 9.1 概要

| 機構 | 役割 |
|------|------|
| **Haskell モジュール** | 語彙（スマートコンストラクタ） |
| **PlatRule インスタンス** | 検証ルール |

### 9.2 語彙拡張

```haskell
module Plat.Ext.DDD where

import Plat.Core

value :: Text -> LayerDef -> DeclWriter () -> Declaration
value name ly body = model name ly $ do
  meta "plat-ddd:kind" "value"
  body

aggregate :: Text -> LayerDef -> DeclWriter () -> Declaration
aggregate name ly body = model name ly $ do
  meta "plat-ddd:kind" "aggregate"
  body

invariant :: Text -> Text -> DeclWriter ()
invariant name expr = meta ("plat-ddd:invariant:" <> name) expr

enum_ :: Text -> LayerDef -> [Text] -> Declaration
enum_ name ly variants = model name ly $ do
  meta "plat-ddd:kind" "enum"
  forM_ variants $ \v -> meta ("plat-ddd:variant:" <> v) v
```

### 9.3 検証ルールの拡張

```haskell
data ValueNoIdRule = ValueNoIdRule

instance PlatRule ValueNoIdRule where
  ruleCode _ = "DDD-V001"
  checkDecl _ _ decl
    | isValue decl, any isIdField (declFields decl)
    = [Diagnostic Error "DDD-V001"
        "value object must not have an Id field"
        (declName decl) Nothing]
    | otherwise = []

dddRules :: [SomeRule]
dddRules = [SomeRule ValueNoIdRule, ...]
```

### 9.4 統合

```haskell
let result = checkWith (coreRules ++ dddRules ++ cqrsRules) architecture
```

### 9.5 ユーザー定義パッケージ

```haskell
module Plat.Ext.MyOrg (myKeyword, myOrgRules) where

import Plat.Core
import Plat.Check.Class

myKeyword :: Text -> LayerDef -> DeclWriter () -> Declaration
myKeyword name ly body = model name ly $ do
  meta "my-org:kind" "my-keyword"
  body

data MyRule = MyRule
instance PlatRule MyRule where ...

myOrgRules :: [SomeRule]
myOrgRules = [SomeRule MyRule]
```

---

## 10. 標準拡張パッケージ

### 10.1 一覧

| Cabal パッケージ | モジュール | 主な語彙 |
|-----------------|----------|---------|
| plat-hs-ddd | `Plat.Ext.DDD` | `value`, `enum_`, `aggregate`, `invariant` |
| plat-hs-dbc | `Plat.Ext.DBC` | `pre`, `post`, `assert_`, `opWithContract` |
| plat-hs-flow | `Plat.Ext.Flow` | `step`, `policy`, `guard_` |
| plat-hs-http | `Plat.Ext.Http` | `controller`, `route`, `presenter`, `view_` |
| plat-hs-events | `Plat.Ext.Events` | `event`, `apply_`, `emit`, `on_` |
| plat-hs-cqrs | `Plat.Ext.CQRS` | `command`, `query` |
| plat-hs-modules | `Plat.Ext.Modules` | `domain`, `expose`, `import_` |
| plat-hs-cleanarch | `Plat.Ext.CleanArch` | `entity`, `usecase`, `port`, `impl_`, `wire` |

### 10.2 `Plat.Ext.DDD`

```haskell
import Plat.Core
import Plat.Ext.DDD

moneyValue :: Declaration
moneyValue = value "Money" core $ do
  field "amount"   int
  field "currency" string
  invariant "nonNegative" "amount >= 0"

orderStatus :: Declaration
orderStatus = enum_ "OrderStatus" core
  ["draft", "placed", "paid", "shipped", "cancelled"]

order :: Declaration
order = aggregate "Order" core $ do
  field "id"     uuid
  field "items"  (list (ref orderItem))
  field "status" (ref orderStatus)
  field "total"  (ref moneyValue)
```

### 10.3 `Plat.Ext.CQRS`

```haskell
import Plat.Core
import Plat.Ext.CQRS

placeOrderCmd :: Declaration
placeOrderCmd = command "PlaceOrder" application $ do
  input  "customerId" uuid
  input  "items"      (list (ref orderItem))
  output "order"      (ref order)
  output "err"        error_
  needs orderRepo

getOrderQuery :: Declaration
getOrderQuery = query "GetOrder" application $ do
  input  "id"    uuid
  output "order" (ref order)
  output "err"   error_
  needs orderRepo
```

### 10.4 `Plat.Ext.CleanArch`

```haskell
import Plat.Core
import Plat.Ext.CleanArch

-- プリセットレイヤー
-- enterprise, application, interface, framework :: LayerDef
-- cleanArchLayers :: [LayerDef]

orderEntity :: Declaration
orderEntity = entity "Order" enterprise $ do
  field "id"    uuid
  field "total" decimal

orderRepoPort :: Declaration
orderRepoPort = port "OrderRepository" interface $ do
  op "save"
    ["order" .: ref orderEntity]
    ["err" .: error_]
```

### 10.5 `Plat.Ext.Http`

HTTP ハンドラの記述。`route` の operation は値参照。

```haskell
import Plat.Core
import Plat.Ext.Http

orderHandler :: Declaration
orderHandler = controller "OrderController" infra $ do
  path "adapter/http/handler.go"
  route POST   "/orders"       placeOrder     -- Declaration 値
  route DELETE "/orders/{id}"  cancelOrder
  route GET    "/orders/{id}"  getOrder
```

`controller` は `adapter` の拡張であり、`implements` なしの adapter として扱われる。

---

## 11. .plat 生成バックエンド

### 11.1 API

```haskell
module Plat.Generate.Plat where

render      :: Architecture -> Text
renderFiles :: Architecture -> [(FilePath, Text)]

data RenderConfig = RenderConfig
  { rcSplitFiles :: Bool
  , rcDesignDir  :: FilePath
  , rcPackageUse :: Bool
  }

defaultConfig :: RenderConfig
renderWith    :: RenderConfig -> Architecture -> [(FilePath, Text)]
```

### 11.2 ファイル分割規則

| 宣言の種類 | 出力先 |
|-----------|--------|
| `layer` | `design/layers.plat` |
| `type` | `design/types.plat` |
| `model` | `design/models/{name}.plat` |
| `operation` | `design/operations/{name}.plat` |
| `boundary` | `design/boundaries/{name}.plat` |
| `adapter` | `design/adapters/{name}.plat` |
| `compose` | `design/compose.plat` |

### 11.3 名前付きパラメータの .plat 出力

eDSL の名前付きパラメータは `.plat` 生成時に positional に変換される。

```
-- eDSL
op "charge"
  ["amount" .: ref money, "cardToken" .: string]
  ["chargeId" .: string, "err" .: error_]

-- .plat 出力
charge: (Money, String) -> (String, Error)
```

パラメータ名は `.plat` には含まれないが、将来の sync チェックでターゲット言語のシグネチャとの照合に使用される。

### 11.4 implements の .plat 出力

`Implements` が DeclItem に含まれる場合は `.plat` の `implements` 句を出力する。含まれない場合は省略。

```
-- implements あり
adapter PostgresOrderRepo : infra implements OrderRepository {
  @ adapter/postgres/order_repo.go
  inject db: *sql.DB
}

-- implements なし
adapter OrderHttpHandler : infra {
  @ adapter/http/handler.go
  inject placeOrder:  PlaceOrder
  inject cancelOrder: CancelOrder
  inject getOrder:    GetOrder
  inject router:      chi.Router
}
```

### 11.5 Mermaid / Markdown

```haskell
module Plat.Generate.Mermaid where
renderMermaid :: Architecture -> Text

module Plat.Generate.Markdown where
renderMarkdown :: Architecture -> Text
```

---

## 12. パッケージ構成と利用

### 12.1 Cabal パッケージ

```
plat-hs              -- Core eDSL + 検証 + 生成
plat-hs-ddd          -- DDD 拡張
plat-hs-dbc          -- DbC 拡張
plat-hs-flow         -- Flow 拡張
plat-hs-http         -- HTTP 拡張
plat-hs-events       -- Events 拡張
plat-hs-cqrs         -- CQRS 拡張
plat-hs-modules      -- Modules 拡張
plat-hs-cleanarch    -- Clean Architecture プリセット
```

### 12.2 ユーザープロジェクト

```cabal
cabal-version: 3.0
name:          my-project-design
version:       0.1.0

executable design-check
  main-is:          Main.hs
  hs-source-dirs:   src
  build-depends:
    , base            >= 4.18 && < 5
    , plat-hs         >= 0.5
    , plat-hs-ddd
    , plat-hs-cqrs
    , plat-hs-cleanarch
  default-language: GHC2021
```

### 12.3 Main.hs テンプレート

```haskell
module Main where

import Plat.Core
import Plat.Check
import Plat.Generate.Plat (renderFiles)
import Plat.Ext.DDD (dddRules)
import Plat.Ext.CQRS (cqrsRules)
import Design.Architecture (architecture)

main :: IO ()
main = do
  let rules  = coreRules ++ dddRules ++ cqrsRules
      result = checkWith rules architecture
  T.putStrLn (prettyCheck result)

  ioResult <- checkIO architecture
  T.putStrLn (prettyCheck ioResult)

  when (hasViolations result || hasViolations ioResult) exitFailure

  let files = renderFiles architecture
  forM_ files $ \(fp, content) -> do
    createDirectoryIfMissing True (takeDirectory fp)
    T.writeFile fp content

  putStrLn $ "✓ " ++ show (length files) ++ " .plat files generated."
```

---

## 13. GHC 要件

**最小**: GHC 9.6 / **推奨**: GHC 9.10 以上

**ユーザーに要求する言語拡張**:

```haskell
{-# LANGUAGE OverloadedStrings #-}
```

**plat-hs 内部で使用する拡張**: `GADTs`（`SomeRule` の存在型）、`OverloadedStrings`。

---

## 14. 利用例 — Go クリーンアーキテクチャ

Go の EC サイト・オーダー管理サービスを plat-hs で記述する完全な例。

### 14.1 プロジェクト構成

```
order-service/
├── design/                      -- plat-hs が生成する .plat
├── design-hs/
│   ├── order-design.cabal
│   └── src/
│       ├── Main.hs
│       └── Design/
│           ├── Layers.hs
│           ├── Models.hs
│           ├── Boundaries.hs
│           ├── Operations.hs
│           ├── Adapters.hs
│           ├── Compose.hs
│           └── Architecture.hs
├── domain/
├── usecase/
├── adapter/
└── cmd/
```

### 14.2 Design/Layers.hs

```haskell
module Design.Layers where

import Plat.Core
import Plat.Ext.CleanArch (cleanArchLayers, enterprise, application, interface, framework)

-- CleanArch プリセットを使用
-- enterprise, application, interface, framework が利用可能
```

### 14.3 Design/Models.hs

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Design.Models where

import Plat.Core
import Plat.Ext.DDD
import Design.Layers

uuid :: TypeExpr
uuid = customType "UUID"

orderStatus :: Declaration
orderStatus = enum_ "OrderStatus" enterprise
  ["draft", "placed", "paid", "shipped", "cancelled"]

money :: Declaration
money = value "Money" enterprise $ do
  field "amount"   int
  field "currency" string
  invariant "nonNegative" "amount >= 0"

orderItem :: Declaration
orderItem = value "OrderItem" enterprise $ do
  field "productId" uuid
  field "quantity"  int
  field "unitPrice" (ref money)

order :: Declaration
order = aggregate "Order" enterprise $ do
  path "domain/order.go"
  field "id"         uuid
  field "customerId" uuid
  field "items"      (list (ref orderItem))
  field "status"     (ref orderStatus)
  field "total"      (ref money)
  field "createdAt"  dateTime
  field "updatedAt"  dateTime
```

### 14.4 Design/Boundaries.hs

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Design.Boundaries where

import Plat.Core
import Design.Layers
import Design.Models

orderRepo :: Declaration
orderRepo = boundary "OrderRepository" interface $ do
  path "usecase/port/order_repo.go"
  op "save"
    ["order" .: ref order]
    ["err" .: error_]
  op "findById"
    ["id" .: uuid]
    ["order" .: ref order, "err" .: error_]
  op "findByCustomer"
    ["customerId" .: uuid]
    ["orders" .: stream (ref order)]

paymentGateway :: Declaration
paymentGateway = boundary "PaymentGateway" interface $ do
  path "usecase/port/payment.go"
  op "charge"
    ["amount" .: ref money, "cardToken" .: string]
    ["chargeId" .: string, "err" .: error_]

eventPublisher :: Declaration
eventPublisher = boundary "EventPublisher" interface $ do
  path "usecase/port/event_pub.go"
  op "publish"
    ["topic" .: string, "payload" .: any_]
    ["err" .: error_]
```

### 14.5 Design/Operations.hs

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Design.Operations where

import Plat.Core
import Plat.Ext.CQRS
import Design.Layers
import Design.Models
import Design.Boundaries

placeOrder :: Declaration
placeOrder = command "PlaceOrder" application $ do
  path "usecase/place_order.go"
  input  "customerId" uuid
  input  "items"      (list (ref orderItem))
  input  "cardToken"  string
  output "order"      (ref order)
  output "err"        error_
  needs orderRepo
  needs paymentGateway
  needs eventPublisher

cancelOrder :: Declaration
cancelOrder = command "CancelOrder" application $ do
  path "usecase/cancel_order.go"
  input  "orderId" uuid
  input  "reason"  string
  output "err"     error_
  needs orderRepo
  needs eventPublisher

getOrder :: Declaration
getOrder = query "GetOrder" application $ do
  path "usecase/get_order.go"
  input  "id"    uuid
  output "order" (ref order)
  output "err"   error_
  needs orderRepo
```

### 14.6 Design/Adapters.hs

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Design.Adapters where

import Plat.Core
import Plat.Ext.Http
import Design.Layers
import Design.Boundaries
import Design.Operations

postgresOrderRepo :: Declaration
postgresOrderRepo = adapter "PostgresOrderRepo" framework $ do
  implements orderRepo
  path "adapter/postgres/order_repo.go"
  inject "db" (ext "*sql.DB")

stripePayment :: Declaration
stripePayment = adapter "StripePayment" framework $ do
  implements paymentGateway
  path "adapter/stripe/payment.go"
  inject "client" (ext "*stripe.Client")

kafkaPublisher :: Declaration
kafkaPublisher = adapter "KafkaEventPublisher" framework $ do
  implements eventPublisher
  path "adapter/kafka/event_pub.go"
  inject "producer" (ext "*kafka.Producer")

orderHandler :: Declaration
orderHandler = controller "OrderController" framework $ do
  path "adapter/http/handler.go"
  route POST   "/orders"       placeOrder
  route DELETE "/orders/{id}"  cancelOrder
  route GET    "/orders/{id}"  getOrder
```

### 14.7 Design/Compose.hs

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Design.Compose where

import Plat.Core
import Design.Boundaries
import Design.Adapters

appRoot :: Declaration
appRoot = compose "AppRoot" $ do
  bind orderRepo       postgresOrderRepo
  bind paymentGateway  stripePayment
  bind eventPublisher  kafkaPublisher
  entry orderHandler
  entry "MainServer"
```

### 14.8 Design/Architecture.hs

```haskell
module Design.Architecture (architecture) where

import Plat.Core
import Plat.Ext.CleanArch (cleanArchLayers)
import Design.Models
import Design.Boundaries
import Design.Operations
import Design.Adapters
import Design.Compose

architecture :: Architecture
architecture = arch "order-service" $ do
  useLayers cleanArchLayers
  registerType "UUID"
  declares [ orderStatus, money, orderItem, order
           , orderRepo, paymentGateway, eventPublisher
           , placeOrder, cancelOrder, getOrder
           , postgresOrderRepo, stripePayment, kafkaPublisher
           , orderHandler
           , appRoot
           ]
```

---

## 15. 利用例 — メタプログラミング

### 15.1 CRUD 一括生成

```haskell
crudBoundary :: Declaration -> LayerDef -> Declaration
crudBoundary entity ly =
  boundary (declName entity <> "Repository") ly $ do
    op "save"
      ["entity" .: ref entity]
      ["err" .: error_]
    op "findById"
      ["id" .: idOf entity]
      ["entity" .: ref entity, "err" .: error_]
    op "findAll"  []  ["entities" .: stream (ref entity)]
    op "delete"
      ["id" .: idOf entity]
      ["err" .: error_]

crudRepos :: [Declaration]
crudRepos = map (\e -> crudBoundary e interface)
  [order, user, product_, category, payment_]
```

### 15.2 レイヤーパターンの比較

```haskell
compareLayouts :: IO ()
compareLayouts = forM_ layouts $ \(name, ls) -> do
  let a = arch "test" $ do
        useLayers ls
        declares sharedDecls
      r = check a
  putStrLn $ name ++ ": " ++ show (length (violations r)) ++ " violations"
  where
    layouts =
      [ ("Hexagonal 3-layer",
          [ layer "domain"
          , layer "app"   `depends` [layer "domain"]
          , layer "infra" `depends` [layer "domain", layer "app" `depends` [layer "domain"]]
          ])
      , ("Clean 4-layer", cleanArchLayers)
      ]
```

### 15.3 adapter 自動ペアリング

```haskell
-- boundary と adapter の命名規約に基づいて bind を自動生成
autoBind :: [(Declaration, Declaration)] -> DeclWriter ()
autoBind pairs = forM_ pairs $ \(bnd, adp) -> bind bnd adp

appRoot :: Declaration
appRoot = compose "AppRoot" $ do
  autoBind [ (orderRepo,      postgresOrderRepo)
           , (paymentGateway, stripePayment)
           , (eventPublisher, kafkaPublisher)
           ]
  entry orderHandler
```

---

## 16. 将来構想

### 16.1 型レベルレイヤー検証

オプショナルモジュール `Plat.Core.Typed` でレイヤー依存をコンパイルエラーとして検出する。

### 16.2 Template Haskell .plat パーサー

```haskell
$(loadPlat "design/models/order.plat")
-- → order :: Declaration
```

### 16.3 QuickCheck プロパティテスト

```haskell
prop_noCircularDeps :: Architecture -> Property
prop_layerInvariant :: Architecture -> Declaration -> Property
```

### 16.4 ターゲット言語プロファイル

`Plat.Lang.Go`, `Plat.Lang.TypeScript` 等で言語固有の型定数・暗黙パラメータ（context.Context 等）・sync チェックアダプターを提供する。

```haskell
import Plat.Lang.Go (ctx)  -- 将来

orderRepo = boundary "OrderRepository" interface $ do
  op "save"
    [ctx, "order" .: ref order]   -- context.Context を暗黙付与
    ["err" .: error_]
```

### 16.5 Rust ツールチェーンとの統合

plat-hs は `.plat` 生成源、Rust ツールチェーンは `plat sync` を担い、`.plat` をインターフェースとして疎結合に連携する。

---

*plat-hs は現在 RFC フェーズです。フィードバックを歓迎します。*

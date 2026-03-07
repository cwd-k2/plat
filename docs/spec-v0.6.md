# plat-hs 仕様書

**バージョン**: 0.6.0-draft
**ステータス**: RFC
**最終更新**: 2026-03-06
**前提**: Plat 仕様 v0.5.0-draft
**リポジトリ名**: `plat-hs`

### v0.5 → v0.6 変更概要

- **`Decl k` 導入**: phantom-tagged newtype で宣言の種類をコンパイル時に区別。`ref`, `needs`, `implements`, `bind` 等の誤用を型エラーにする
- **`DeclKind` リネーム**: `KModel` → `Model`, `KBoundary` → `Boundary` 等（promoted type として自然に読める）
- **`DeclWriter k` / `ArchBuilder` 正式定義**: ビルダーモナドの型・内部状態・意味論を明記
- **DeclKind × コンビネータ許容マトリクス**: どの宣言種でどのコンビネータが使えるかを表で規定
- **`Meta` を `DeclItem` から分離**: `declMeta :: [(Text, Text)]` としてメタデータの関心を分離
- **`IsEntry Text` 廃止**: H2 厳守のため `entryName :: Text` を明示的エスケープハッチとして分離
- **`implements` 多重度**: adapter 内で最大 1 回。複数呼び出し時は最後の値を採用
- **予約型参照**: `Error`, `Id` を W002 免除の予約型として明記
- **`coreRules` 列挙**: V001〜V008, W001〜W003 の所属を明記
- **`.plat` 出力フォーマット**: 各宣言種の出力構文を明記
- **標準拡張**: 独立パッケージから `plat-hs` 内モジュールに変更（将来の分割は需要に応じて判断）
- **命名規約**: Haskell 予約語との衝突回避（trailing underscore）を統一的に文書化
- **H2 / H3 の主張を精緻化**: 型安全性の範囲を正確に記述
- **`Op` / `Input`・`Output` 非対称性**: 設計根拠を文書化

---

## 目次

1. [概要と位置づけ](#1-概要と位置づけ)
2. [設計方針](#2-設計方針)
3. [アーキテクチャ](#3-アーキテクチャ)
4. [Core eDSL — 参照モデル](#4-core-edsl--参照モデル)
5. [Core eDSL — AST](#5-core-edsl--ast)
6. [Core eDSL — ビルダーモナド](#6-core-edsl--ビルダーモナド)
7. [Core eDSL — 宣言構文](#7-core-edsl--宣言構文)
8. [型式システム](#8-型式システム)
9. [検証システム](#9-検証システム)
10. [拡張システム](#10-拡張システム)
11. [標準拡張モジュール](#11-標準拡張モジュール)
12. [.plat 生成バックエンド](#12-plat-生成バックエンド)
13. [パッケージ構成と利用](#13-パッケージ構成と利用)
14. [GHC 要件](#14-ghc-要件)
15. [利用例 — Go クリーンアーキテクチャ](#15-利用例--go-クリーンアーキテクチャ)
16. [利用例 — メタプログラミング](#16-利用例--メタプログラミング)
17. [将来構想](#17-将来構想)

---

## 1. 概要と位置づけ

### 1.1 plat-hs とは

plat-hs は Plat（アーキテクチャ設計支援ツール）の **Haskell eDSL 実装**である。

**ねらい**: ソフトウェアの設計を議論するとき、言語の構文、ディレクトリ構造、フレームワークの作法、DI コンテナの設定など、実装上の関心事に議論が引きずられることが多い。plat-hs は、これらの実装詳細から**設計・アーキテクチャだけを抽出**し、「何がどのレイヤーにあり、何が何に依存しているか」という構造の検討に専念できる環境を提供することを目指す。Go で書くか TypeScript で書くか、gin を使うか chi を使うかに関わらず、設計の骨格は同じ eDSL で記述・検証できる。

`.plat` ファイルの記法を Haskell の値参照と do 記法で表現し、以下を提供する。

- **設計記述**: model / boundary / operation 等を Haskell の値として記述する
- **参照安全性**: 宣言間の参照を変数束縛で表現し、typo をコンパイルエラーにする
- **構造安全性**: phantom type により宣言種の誤用（model への `needs` 等）をコンパイルエラーにする
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
| 宣言種の構造安全性 | phantom type + kind promotion |
| 宣言的な設計記述 | do 記法 |
| 検証ルールの合成・拡張 | 型クラス + 代数的データ型 |
| パッケージ拡張 | Haskell モジュール + 型クラスインスタンス |
| メタプログラミング | 通常の関数・リスト操作 |

---

## 2. 設計方針

**H1 — Plat 仕様への忠実性**
Plat v0.5 の Core 仕様を完全に表現する。Haskell 固有の追加は Plat の方針（P1〜P6）と矛盾しない範囲に限る。

**H2 — 値による参照**
宣言間の参照はすべて Haskell の変数束縛で表現する。文字列による参照は**命名**（.plat 出力用の識別子）と**パス**（ファイルパス）に限定する。なお、`entryName` 等の明示的エスケープハッチは H2 の例外として提供するが、通常の使用では値参照を推奨する。

**H3 — 宣言の二層モデル**
eDSL の構築時は `Decl k`（phantom-tagged）により宣言種ごとの型安全性を保つ。AST としては均質な `Declaration` 型であり、リスト・関数で自然に操作できる。構築の安全性と操作の均質性を両立する。

**H4 — 名前は宣言に属し、参照は値に属す**
.plat に出力される識別子だけが文字列。他の宣言からの参照はすべて値経由。

**H5 — 型も値**
ビルトイン型・model 参照・カスタム型をすべて `TypeExpr` の値として提供する。

**H6 — 生成物としての .plat**
生成された `.plat` は手書きと区別がつかない正規ファイル。

**H7 — 柔軟な構造パターン**
adapter は boundary を implements するものだけでなく、HTTP ハンドラ・CLI・gRPC server 等の入口コンポーネントも表現できる。実プロジェクトの多様な構造に対応する。

---

## 3. アーキテクチャ

### 3.1 モジュール構成

```
plat-hs/
├── Plat/
│   ├── Core.hs                -- 公開 API の再エクスポート
│   ├── Core/
│   │   ├── Types.hs           -- AST 定義 (Declaration, Decl k, DeclItem, ...)
│   │   ├── Builder.hs         -- DeclWriter k / ArchBuilder
│   │   └── TypeExpr.hs        -- 型式: ビルトイン + コンストラクタ
│   ├── Check.hs               -- 検証エンジン（再エクスポート）
│   ├── Check/
│   │   ├── Rules.hs           -- Core 検証ルール (V001〜V008, W001〜W003)
│   │   └── Class.hs           -- PlatRule 型クラス（拡張ポイント）
│   ├── Generate.hs            -- 生成エンジン（再エクスポート）
│   ├── Generate/
│   │   ├── Plat.hs            -- .plat フォーマッタ
│   │   ├── Mermaid.hs         -- Mermaid 図
│   │   └── Markdown.hs        -- Markdown ドキュメント
│   └── Ext/                   -- 標準拡張モジュール
│       ├── DDD.hs
│       ├── DBC.hs
│       ├── Flow.hs
│       ├── Http.hs
│       ├── Events.hs
│       ├── CQRS.hs
│       ├── Modules.hs
│       └── CleanArch.hs
```

### 3.2 データフロー

```
ユーザーの .hs
    │  import Plat.Core
    ▼
eDSL 式（Decl k + do 記法）
    │
    ▼
Architecture（AST: Declaration ベース）
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
|------|------|------|
| **命名** | 文字列 | `model "Order"`, `op "save"` |
| **レイヤー参照** | `LayerDef` 値 | `model "Order" core` |
| **宣言間参照** | `Decl k` 値 | `needs orderRepo`, `bind orderRepo pgRepo` |
| **型参照** | `TypeExpr` 値 | `field "total" decimal`, `ref order` |

文字列が残るのは**命名**（.plat 出力用の識別子）と**パス**（`path "src/..."` のファイルパス）のみ。`entryName` は Plat 宣言を持たない外部コンポーネントへの明示的エスケープハッチである。

### 4.2 参照の解決

eDSL の値参照は、AST 構築時に名前文字列に解決される。AST は文字列ベースであり `.plat` と 1:1 対応を保つ。

```
eDSL                              AST
needs orderRepo            →    Needs "OrderRepository"
field "total" decimal      →    Field "total" (TBuiltin BDecimal)
ref order                  →    TRef "Order"
implements orderRepo       →    Implements "OrderRepository"
bind orderRepo pgRepo      →    Bind "OrderRepository" "PostgresOrderRepo"
```

### 4.3 型安全性の範囲

plat-hs が GHC コンパイル時に保証するのは以下の 2 点である。

1. **参照の存在**: 未定義の変数を参照するとコンパイルエラー（typo 防止）
2. **宣言種の整合性**: `Decl k` の phantom type により、`needs` に model を渡す、`implements` に operation を渡す等の誤用がコンパイルエラー

以下は**コンパイル時には検出できず、`check` による実行時検証**に委ねられる。

- レイヤー依存関係の違反（V001）
- 同名の宣言の重複
- `DeclItem` の意味的な整合性（boundary の op が実装されているか等）

---

## 5. Core eDSL — AST

### 5.1 `Plat.Core.Types`

```haskell
module Plat.Core.Types where

import Data.Text (Text)

-- | 宣言の種類（値レベル + DataKinds で型レベルに昇格）
data DeclKind
  = Model
  | Boundary
  | Operation
  | Adapter
  | Compose
  deriving (Show, Eq, Ord)

-- | アーキテクチャ全体
data Architecture = Architecture
  { archName        :: Text
  , archLayers      :: [LayerDef]
  , archTypes       :: [TypeAlias]
  , archCustomTypes :: [Text]           -- registerType で登録された型名
  , archDecls       :: [Declaration]
  , archMeta        :: [(Text, Text)]
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

-- | 宣言（AST ノード、均質な値）
data Declaration = Declaration
  { declKind  :: DeclKind
  , declName  :: Text
  , declLayer :: Maybe Text
  , declPaths :: [FilePath]
  , declBody  :: [DeclItem]
  , declMeta  :: [(Text, Text)]
  } deriving (Show, Eq)

-- | phantom-tagged 宣言（eDSL 構築時の型安全性）
newtype Decl (k :: DeclKind) = Decl { unDecl :: Declaration }
  deriving (Show, Eq)

-- | phantom tag の消去
decl :: Decl k -> Declaration
decl = unDecl

-- | 宣言内の構造要素
data DeclItem
  = Field      Text TypeExpr            -- model: フィールド
  | Op         Text [Param] [Param]     -- boundary: 操作シグネチャ (名前, 入力, 出力)
  | Input      Text TypeExpr            -- operation: 入力パラメータ
  | Output     Text TypeExpr            -- operation: 出力パラメータ
  | Needs      Text                     -- operation: 依存 boundary 名
  | Implements Text                     -- adapter: 実装対象 boundary 名 (最大 1)
  | Inject     Text TypeExpr            -- adapter: DI 注入
  | Bind       Text Text               -- compose: boundary → adapter の束縛
  | Entry      Text                     -- compose: エントリポイント
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
  deriving (Show, Eq, Ord)

-- | ビルトイン型
data Builtin
  = BString | BInt | BFloat | BDecimal
  | BBool | BUnit | BBytes | BDateTime
  | BAny
  deriving (Show, Eq, Ord, Enum, Bounded)
```

### 5.2 DeclKind × DeclItem 許容マトリクス

各 `DeclKind` で使用できるコンビネータを規定する。`DeclWriter k` の phantom type により**コンパイル時に強制**される。

| コンビネータ | `Model` | `Boundary` | `Operation` | `Adapter` | `Compose` |
|-------------|---------|------------|-------------|-----------|-----------|
| `field` | **✓** | | | | |
| `op` / `op'` | | **✓** | | | |
| `input` | | | **✓** | | |
| `output` | | | **✓** | | |
| `needs` | | | **✓** | | |
| `implements` | | | | **✓** (0..1) | |
| `inject` | | | | **✓** | |
| `bind` | | | | | **✓** |
| `entry` / `entryName` | | | | | **✓** |
| `path` | **✓** | **✓** | **✓** | **✓** | |
| `meta` | **✓** | **✓** | **✓** | **✓** | **✓** |

**`implements` の多重度**: adapter 内で最大 1 回。複数回呼び出した場合、最後の値が採用される。`Implements` を含まない adapter も有効である（HTTP ハンドラ等、H7 参照）。

### 5.3 `Op` と `Input`/`Output` の設計根拠

boundary は**複数の操作シグネチャ**を持つインターフェースであり、各 `Op` が名前・入力・出力を一つの単位として保持する。operation は**単一の処理単位**であり、`Input`/`Output` は個別のパラメータとして蓄積される。

この非対称性は意図的である。boundary の op はシグネチャ全体がアトミックな単位（「この入力を受けてこの出力を返す」）であり、operation の input/output は処理の入出力パラメータの列挙である。将来の sync チェック（W004）では、boundary op のシグネチャと operation の input/output 集合を構造的に比較する。

### 5.4 v0.5 からの AST 変更点

| 項目 | v0.5 | v0.6 | 理由 |
|------|------|------|------|
| `Declaration` | 直接使用 | `Decl k` (phantom) + `Declaration` (erased) | 構築時の型安全性 |
| `DeclKind` | `KModel`, `KBoundary`, ... | `Model`, `Boundary`, ... | promoted type として自然 |
| `Meta` | `DeclItem` のバリアント | `declMeta :: [(Text, Text)]` | 構造要素とメタデータの分離 |
| `declMeta` | `Map Text Text` | `[(Text, Text)]` | 挿入順序の保持 |

---

## 6. Core eDSL — ビルダーモナド

### 6.1 `DeclWriter k`

`DeclWriter k` は宣言の本体を構築するモナドである。phantom type `k :: DeclKind` により、各宣言種で有効なコンビネータのみが型レベルで許可される。

```haskell
module Plat.Core.Builder where

-- | ビルダー内部状態（非公開）
data DeclBuild = DeclBuild
  { dbItems :: [DeclItem]       -- 構造要素（逆順で蓄積、構築時に反転）
  , dbPaths :: [FilePath]       -- @path 注釈
  , dbMeta  :: [(Text, Text)]   -- メタデータ（逆順で蓄積）
  }

emptyDeclBuild :: DeclBuild
emptyDeclBuild = DeclBuild [] [] []

-- | 宣言ビルダーモナド（k は DeclKind の promoted type）
newtype DeclWriter (k :: DeclKind) a = DeclWriter (State DeclBuild a)
  deriving newtype (Functor, Applicative, Monad)

-- | ビルダーの実行（非公開）
runDeclWriter :: DeclWriter k a -> DeclBuild
runDeclWriter (DeclWriter s) = execState s emptyDeclBuild
```

**設計判断**: `DeclWriter k` の phantom parameter `k` はランタイムに影響しない（newtype はゼロコスト抽象）。`State DeclBuild` が実際の計算を担い、`k` はコンビネータの型シグネチャでのみ使用される。

### 6.2 `DeclWriter` コンビネータの型シグネチャ

```haskell
-- Model 専用
field :: Text -> TypeExpr -> DeclWriter 'Model ()

-- Boundary 専用
op  :: Text -> [Param] -> [Param] -> DeclWriter 'Boundary ()
op' :: Text -> [Param] -> TypeExpr -> DeclWriter 'Boundary ()

-- Operation 専用
input  :: Text -> TypeExpr -> DeclWriter 'Operation ()
output :: Text -> TypeExpr -> DeclWriter 'Operation ()
needs  :: Decl 'Boundary -> DeclWriter 'Operation ()

-- Adapter 専用
implements :: Decl 'Boundary -> DeclWriter 'Adapter ()
inject     :: Text -> TypeExpr -> DeclWriter 'Adapter ()

-- Compose 専用
bind      :: Decl 'Boundary -> Decl 'Adapter -> DeclWriter 'Compose ()
entry     :: Decl k -> DeclWriter 'Compose ()
entryName :: Text -> DeclWriter 'Compose ()

-- 全 DeclKind 共通
meta :: Text -> Text -> DeclWriter k ()

-- Compose 以外（HasPath 制約）
path :: HasPath k => FilePath -> DeclWriter k ()

class HasPath (k :: DeclKind)
instance HasPath 'Model
instance HasPath 'Boundary
instance HasPath 'Operation
instance HasPath 'Adapter
```

### 6.3 `ArchBuilder`

`ArchBuilder` はアーキテクチャ全体を構築するモナドである。

```haskell
-- | アーキテクチャビルダー内部状態（非公開）
data ArchBuild = ArchBuild
  { abLayers      :: [LayerDef]
  , abTypes       :: [TypeAlias]
  , abCustomTypes :: [Text]
  , abDecls       :: [Declaration]
  , abMeta        :: [(Text, Text)]
  }

newtype ArchBuilder a = ArchBuilder (State ArchBuild a)
  deriving newtype (Functor, Applicative, Monad)
```

```haskell
-- | アーキテクチャ構築
arch :: Text -> ArchBuilder () -> Architecture

-- | レイヤー登録
useLayers :: [LayerDef] -> ArchBuilder ()

-- | 型エイリアス登録
useTypes :: [TypeAlias] -> ArchBuilder ()

-- | カスタム型登録（W002 検証で認識される）
registerType :: Text -> ArchBuilder ()

-- | 宣言登録（型安全: Decl k を受け付ける）
declare :: Decl k -> ArchBuilder ()

-- | 宣言の一括登録（メタプログラミング用: erased Declaration を受け付ける）
declares :: [Declaration] -> ArchBuilder ()
```

### 6.4 スマートコンストラクタの実装モデル

スマートコンストラクタは `DeclWriter k` を実行し、内部状態から `Declaration` を構築して `Decl k` で包む。

```haskell
model :: Text -> LayerDef -> DeclWriter 'Model () -> Decl 'Model
model name ly body = Decl Declaration
  { declKind  = Model
  , declName  = name
  , declLayer = Just (layerName ly)
  , declPaths = reverse (dbPaths build)
  , declBody  = reverse (dbItems build)
  , declMeta  = reverse (dbMeta build)
  }
  where build = runDeclWriter body
```

他のスマートコンストラクタ（`boundary`, `operation`, `adapter`）も同様の構造を持つ。`compose` のみ `declLayer = Nothing` となる（§7.7 参照）。

---

## 7. Core eDSL — 宣言構文

### 7.1 レイヤー定義

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

### 7.2 型エイリアス

```haskell
(=:)  :: Text -> TypeExpr -> TypeAlias
alias :: TypeAlias -> TypeExpr
```

`alias` は `TypeAlias` の値から `TypeExpr`（`TRef aliasName`）を生成する。名前が `TypeAlias` 自体と紛らわしいため、将来のリネーム候補であるが、v0.6 では互換性を維持する。

```haskell
money        = "Money"        =: decimal
emailAddress = "EmailAddress" =: string
orderItems   = "OrderItems"   =: list (ref orderItem)
```

### 7.3 モデル

```haskell
model :: Text -> LayerDef -> DeclWriter 'Model () -> Decl 'Model
field :: Text -> TypeExpr -> DeclWriter 'Model ()
path  :: HasPath k => FilePath -> DeclWriter k ()
```

```haskell
orderItem :: Decl 'Model
orderItem = model "OrderItem" core $ do
  field "productId" uuid
  field "quantity"  int
  field "unitPrice" (alias money)

order :: Decl 'Model
order = model "Order" core $ do
  path "domain/order.go"
  field "id"         uuid
  field "customerId" uuid
  field "items"      (list (ref orderItem))
  field "status"     (ref orderStatus)
  field "total"      (alias money)
  field "createdAt"  dateTime
  field "updatedAt"  dateTime
```

### 7.4 バウンダリ — 名前付きシグネチャ

```haskell
boundary :: Text -> LayerDef -> DeclWriter 'Boundary () -> Decl 'Boundary
op       :: Text -> [Param] -> [Param] -> DeclWriter 'Boundary ()

-- | Param ヘルパー（中置演算子）
(.:) :: Text -> TypeExpr -> Param
```

`(.:)` 演算子により、パラメータを `"name" .: type` で宣言する。

```haskell
orderRepo :: Decl 'Boundary
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

paymentGateway :: Decl 'Boundary
paymentGateway = boundary "PaymentGateway" interface $ do
  path "usecase/port/payment.go"
  op "charge"
    ["amount" .: alias money, "cardToken" .: string]
    ["chargeId" .: string, "err" .: error_]

eventPublisher :: Decl 'Boundary
eventPublisher = boundary "EventPublisher" interface $ do
  path "usecase/port/event_pub.go"
  op "publish"
    ["topic" .: string, "payload" .: any_]
    ["err" .: error_]
```

**設計判断**: `.plat` の boundary op は `save: (Order) -> Result<Unit, Error>` という positional な記法だが、plat-hs ではパラメータ名を保持する。.plat 生成時に名前を落としても、eDSL の可読性と将来の sync チェック精度が向上する。Go/TypeScript の名前付き引数の慣習にも合致する。

**単一返却のショートハンド**:

```haskell
-- | 単一返却のショートハンド
op' :: Text -> [Param] -> TypeExpr -> DeclWriter 'Boundary ()
op' name params retType = op name params ["_" .: retType]
```

```haskell
op "findAll" [] ["orders" .: stream (ref order)]   -- 名前付き
op' "count"  [] int                                 -- ショートハンド
```

### 7.5 オペレーション

```haskell
operation :: Text -> LayerDef -> DeclWriter 'Operation () -> Decl 'Operation
input     :: Text -> TypeExpr -> DeclWriter 'Operation ()
output    :: Text -> TypeExpr -> DeclWriter 'Operation ()
needs     :: Decl 'Boundary -> DeclWriter 'Operation ()
```

`needs` は `Decl 'Boundary` のみを受け付ける。model や adapter を渡すとコンパイルエラーになる。

```haskell
placeOrder :: Decl 'Operation
placeOrder = operation "PlaceOrder" application $ do
  path "usecase/place_order.go"
  input  "customerId" uuid
  input  "items"      (list (ref orderItem))
  input  "cardToken"  string
  output "order"      (ref order)
  output "err"        error_
  needs orderRepo          -- ✓ Decl 'Boundary
  needs paymentGateway     -- ✓ Decl 'Boundary
  needs eventPublisher     -- ✓ Decl 'Boundary
  -- needs order           -- ✗ コンパイルエラー: Decl 'Model ≠ Decl 'Boundary
```

**input に model 参照を使うパターン**: DTO/Command 構造体がドメインモデルと分離している場合。

```haskell
placeOrderInput :: Decl 'Model
placeOrderInput = model "PlaceOrderInput" application $ do
  field "customerId" uuid
  field "items"      (list (ref orderItem))
  field "cardToken"  string

placeOrder :: Decl 'Operation
placeOrder = operation "PlaceOrder" application $ do
  path "usecase/place_order.go"
  input  "cmd" (ref placeOrderInput)
  output "res" (result (ref order) error_)
  needs orderRepo
```

### 7.6 アダプター

```haskell
adapter    :: Text -> LayerDef -> DeclWriter 'Adapter () -> Decl 'Adapter
implements :: Decl 'Boundary -> DeclWriter 'Adapter ()
inject     :: Text -> TypeExpr -> DeclWriter 'Adapter ()
```

`implements` は `DeclWriter 'Adapter` 内のコンビネータ。`Decl 'Boundary` のみを受け付ける。adapter 内で最大 1 回呼び出せる。複数回呼び出した場合、最後の値が採用される。省略可。

```haskell
-- boundary を implements する adapter
postgresOrderRepo :: Decl 'Adapter
postgresOrderRepo = adapter "PostgresOrderRepo" infra $ do
  implements orderRepo                        -- Decl 'Boundary を値参照
  path "adapter/postgres/order_repo.go"
  inject "db" (ext "*sql.DB")

stripePayment :: Decl 'Adapter
stripePayment = adapter "StripePayment" infra $ do
  implements paymentGateway
  path "adapter/stripe/payment.go"
  inject "client" (ext "*stripe.Client")

-- implements なしの adapter（HTTP ハンドラ、CLI 等）
httpHandler :: Decl 'Adapter
httpHandler = adapter "OrderHttpHandler" infra $ do
  path "adapter/http/handler.go"
  inject "placeOrder"  (ref placeOrder)
  inject "cancelOrder" (ref cancelOrder)
  inject "getOrder"    (ref getOrder)
  inject "router"      (ext "chi.Router")
```

adapter の構文は `implements` の有無に関わらず同じ `adapter name layer $ do ...` の形をとる。`implements` がある場合のみ V007（boundary の op 未宣言）の検証対象となる。レイヤー依存（V001）はどちらの場合も検証される。

**設計判断**: `implements` をビルダー内コンビネータにすることで、adapter の記述が完全に統一される。ビルダー内であれば `path`, `inject` と同列に読め、宣言の冒頭に置く慣習で boundary との関係が一目で分かる。

### 7.7 コンポーズ

```haskell
compose   :: Text -> DeclWriter 'Compose () -> Decl 'Compose
bind      :: Decl 'Boundary -> Decl 'Adapter -> DeclWriter 'Compose ()
entry     :: Decl k -> DeclWriter 'Compose ()
entryName :: Text -> DeclWriter 'Compose ()
```

`compose` は**レイヤーを持たない**唯一の宣言種である。compose はレイヤー横断的な配線を記述するものであり、特定のレイヤーに属さない。`declLayer` は `Nothing` となる。

`entry` は任意の `Decl k` を受け付ける。`entryName` は Plat 宣言を持たない外部コンポーネントへのエスケープハッチであり、H2 の明示的例外である。通常の使用では `entry`（値参照）を推奨する。

`bind` は `Decl 'Boundary` と `Decl 'Adapter` のペアのみを受け付ける。boundary 同士や adapter 同士の bind はコンパイルエラーとなる。

```haskell
appRoot :: Decl 'Compose
appRoot = compose "AppRoot" $ do
  bind orderRepo       postgresOrderRepo    -- ✓ Boundary × Adapter
  bind paymentGateway  stripePayment        -- ✓ Boundary × Adapter
  bind eventPublisher  kafkaPublisher       -- ✓ Boundary × Adapter
  entry httpHandler                         -- Decl 'Adapter → 値参照
  entryName "MainServer"                    -- 明示的エスケープハッチ
```

### 7.8 アーキテクチャ全体

```haskell
arch         :: Text -> ArchBuilder () -> Architecture
useLayers    :: [LayerDef] -> ArchBuilder ()
useTypes     :: [TypeAlias] -> ArchBuilder ()
registerType :: Text -> ArchBuilder ()
declare      :: Decl k -> ArchBuilder ()
declares     :: [Declaration] -> ArchBuilder ()
```

`declare` は `Decl k` を受け取り、phantom tag を消去して `Declaration` として登録する。`declares` は erased な `[Declaration]` を受け取り、メタプログラミングで生成した宣言リストの一括登録に使う。

```haskell
architecture :: Architecture
architecture = arch "order-service" $ do
  useLayers [core, application, interface, infra]
  useTypes  [money, emailAddress]
  registerType "UUID"

  -- Domain models
  declare orderStatus
  declare orderItem
  declare order

  -- Ports
  declare orderRepo
  declare paymentGateway
  declare eventPublisher

  -- Use cases
  declare placeOrder
  declare cancelOrder
  declare getOrder

  -- Adapters
  declare postgresOrderRepo
  declare stripePayment
  declare kafkaPublisher
  declare httpHandler

  -- Composition
  declare appRoot
```

---

## 8. 型式システム

### 8.1 ビルトイン型（定数値）

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

### 8.2 ジェネリック型コンストラクタ

```haskell
result   :: TypeExpr -> TypeExpr -> TypeExpr  -- Result<T, E>
option   :: TypeExpr -> TypeExpr              -- Option<T>
list     :: TypeExpr -> TypeExpr              -- List<T>
set      :: TypeExpr -> TypeExpr              -- Set<T>
mapType  :: TypeExpr -> TypeExpr -> TypeExpr  -- Map<K, V>
stream   :: TypeExpr -> TypeExpr              -- Stream<T>
nullable :: TypeExpr -> TypeExpr              -- T?
```

### 8.3 参照

```haskell
-- | model / boundary / operation への型参照
ref :: Referenceable k => Decl k -> TypeExpr

-- | model の Id 型（Id<T> を生成）
idOf :: Decl 'Model -> TypeExpr

-- | TypeAlias への参照
alias :: TypeAlias -> TypeExpr

-- | Referenceable: 型参照を生成できる宣言種
class Referenceable (k :: DeclKind)
instance Referenceable 'Model
instance Referenceable 'Boundary
instance Referenceable 'Operation
```

`ref` は `Referenceable` 制約により、`Decl 'Model`, `Decl 'Boundary`, `Decl 'Operation` のみを受け付ける。`Decl 'Adapter` と `Decl 'Compose` への `ref` はコンパイルエラーとなる。

`idOf` は `Decl 'Model` 専用であり、`TGeneric "Id" [TRef name]` を生成する。`Id` は予約ジェネリック型である（§8.5 参照）。

### 8.4 外部型とカスタム型

```haskell
-- | ターゲット言語固有の外部型（inject 用、W002 検証対象外）
ext :: Text -> TypeExpr

-- | プロジェクト定義のカスタム型（registerType で登録、W002 検証対象）
customType :: Text -> TypeExpr
```

| 関数 | 用途 | W002 検証 | 例 |
|------|------|----------|------|
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

### 8.5 予約型参照

以下の型名は plat-hs が予約しており、`registerType` なしで使用でき、W002 の検証対象外である。

| 予約名 | 生成元 | TypeExpr |
|--------|-------|----------|
| `Error` | `error_` | `TRef "Error"` |
| `Id` | `idOf` | `TGeneric "Id" [...]` |

```haskell
-- | Error 型（Haskell の error との衝突回避）
error_ :: TypeExpr
error_ = TRef "Error"
```

`Error` は言語横断的なエラー概念を表す。Go の `error`, TypeScript の `Error`, Rust の `E` 等に対応する。具体的な型マッピングはターゲット言語プロファイル（§17.4）で将来定義される。

### 8.6 命名規約 — Haskell 予約語との衝突回避

Haskell の予約語やよく使われる Prelude の名前と衝突する識別子には **trailing underscore** を付与する。

| plat-hs 名 | 回避対象 | 用途 |
|------------|---------|------|
| `error_` | `Prelude.error` | Error 型参照 |
| `any_` | `Prelude.any` | Any ビルトイン型 |
| `enum_` | (拡張) | DDD enum 宣言 |
| `assert_` | (拡張) | DbC アサーション |
| `view_` | (拡張) | HTTP view |
| `import_` | `import` キーワード | Modules import |
| `on_` | (拡張) | Events ハンドラ |
| `url_` | (慣習例) | URL カスタム型 |

この規約は一貫して trailing underscore を使用する。leading underscore（`_error`）は Haskell で「未使用変数」の慣習があるため避ける。

### 8.7 利用例まとめ

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
  ["err" .: error_]                              -- 予約型
```

---

## 9. 検証システム

### 9.1 コンパイル時 vs 実行時

| 違反 | GHC コンパイル時 | check 実行時 |
|------|-----------------|-------------|
| 未定義の宣言・boundary への参照 | ✓ 変数未定義 | — |
| needs / bind / implements の参照先 typo | ✓ 変数未定義 | — |
| needs に model / adapter を指定 | ✓ `Decl 'Boundary` 不一致 | — |
| bind の引数種の取り違え | ✓ `Decl 'Boundary` × `Decl 'Adapter` 不一致 | — |
| ref に adapter / compose を指定 | ✓ `Referenceable` 制約不一致 | — |
| model 内で op / inject を使用 | ✓ `DeclWriter 'Model` ≠ `DeclWriter 'Boundary` | — |
| V001 レイヤー依存違反 | — | ✓ |
| V002 レイヤー循環依存 | — | ✓ |
| V003 needs に adapter 型 | ✓ (v0.6 で解消) | — |
| V004 boundary に adapter 型 | — | ✓ |
| V005 compose 外での bind | ✓ (v0.6 で解消) | — |
| V006 パッケージキーワード衝突 | — | ✓ |
| V007 adapter が boundary の op を未宣言 | — | ✓（implements ありのみ） |
| V008 存在しない boundary への bind | ✓ (v0.6 で解消) | — |
| W001 未解決の boundary | — | ✓ |
| W002 未定義型名 | — | ✓（ext・予約型除外） |
| W003 @path のファイル不在 | — | ✓（checkIO） |

**v0.6 での改善**: V003, V005, V008 は phantom type の導入によりコンパイル時に検出されるようになった。ランタイムルールとしても残すが、eDSL 経由の構築では到達不能となる。

### 9.2 API

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

check       :: Architecture -> CheckResult
checkIO     :: Architecture -> IO CheckResult
checkWith   :: [SomeRule] -> Architecture -> CheckResult
prettyCheck :: CheckResult -> Text
checkOrFail :: Architecture -> IO ()

hasViolations :: CheckResult -> Bool
hasWarnings   :: CheckResult -> Bool
```

**`check` と `checkIO` の関係**: `check` は純粋な検証（V001〜V008, W001〜W002）を実行する。`checkIO` は `check` の結果に加えて W003（ファイル存在確認）を IO で実行し、両者を結合して返す。

**`checkOrFail`**: `check` と `checkIO` の両方を実行し、violation がある場合に `exitFailure` する。

### 9.3 検証ルール型クラス

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

### 9.4 Core ルール一覧

`coreRules` に含まれるルールの全量を以下に示す。

| コード | 種別 | ルール名 | 検証内容 |
|--------|------|---------|---------|
| V001 | Error | `LayerDepRule` | 宣言のレイヤーが依存先のレイヤーに依存しているか |
| V002 | Error | `LayerCycleRule` | レイヤー定義に循環がないか（`checkArch`） |
| V003 | Error | `NeedsKindRule` | needs の対象が boundary であるか |
| V004 | Error | `BoundaryKindRule` | boundary 宣言が adapter 種でないか |
| V005 | Error | `BindScopeRule` | bind が compose 内にのみ存在するか |
| V006 | Error | `KeywordCollisionRule` | 宣言名がパッケージ予約語と衝突しないか（`checkArch`） |
| V007 | Error | `AdapterCoverageRule` | implements adapter が boundary の全 op を持つか |
| V008 | Error | `BindTargetRule` | bind の左辺が boundary、右辺が adapter であるか |
| W001 | Warning | `UnresolvedBoundaryRule` | 全 boundary に対応する adapter (implements) が存在するか |
| W002 | Warning | `UndefinedTypeRule` | TypeExpr 内の TRef が model/TypeAlias/customType/予約型で解決できるか（ext 除外） |
| W003 | Warning | `PathExistsRule` | @path のファイルが実際に存在するか（`checkIO` 専用） |

```haskell
coreRules :: [SomeRule]
coreRules =
  [ SomeRule LayerDepRule
  , SomeRule LayerCycleRule
  , SomeRule NeedsKindRule
  , SomeRule BoundaryKindRule
  , SomeRule BindScopeRule
  , SomeRule KeywordCollisionRule
  , SomeRule AdapterCoverageRule
  , SomeRule BindTargetRule
  , SomeRule UnresolvedBoundaryRule
  , SomeRule UndefinedTypeRule
  , SomeRule PathExistsRule
  ]
```

### 9.5 V007 の条件付き適用

V007（adapter が boundary の op を未宣言）は `Implements` を含む adapter にのみ適用する。

```haskell
instance PlatRule AdapterCoverageRule where
  ruleCode _ = "V007"
  checkDecl _ arch decl = case declKind decl of
    Adapter
      | Just bndName <- findImplements (declBody decl) -> ...  -- 検証
    _ -> []

-- | DeclItem リストから Implements を探す（最大 1 つ）
findImplements :: [DeclItem] -> Maybe Text
findImplements items =
  listToMaybe [name | Implements name <- items]
```

### 9.6 W002 の検証対象

W002（未定義型名）は以下の `TypeExpr` を検査する。

| TypeExpr | 検証対象 | 理由 |
|----------|---------|------|
| `TRef name` | **対象**（下記除外を除く） | model/TypeAlias/customType で解決できるべき |
| `TRef "Error"` | 除外 | 予約型参照 |
| `TGeneric "Id" [...]` | 除外（`Id` 部分） | 予約ジェネリック型 |
| `TBuiltin _` | 除外 | ビルトイン |
| `TGeneric name [...]` | `name` が `ext` 由来なら除外 | 外部型 |

`ext` で生成された `TypeExpr` は `TRef` だが、検証エンジンは `ext` 由来かどうかを判別する必要がある。実装方針として、`ext` は `TGeneric` の特殊形式（例: `TGeneric "$ext" [TRef name]`）を生成するか、もしくは `Architecture` に ext 型の一覧を保持する。具体的な実装はライブラリの判断に委ねるが、**`ext` 由来の型は W002 の対象外**という意味論は規定する。

---

## 10. 拡張システム

### 10.1 概要

| 機構 | 役割 |
|------|------|
| **Haskell モジュール** | 語彙（スマートコンストラクタ） |
| **PlatRule インスタンス** | 検証ルール |

### 10.2 語彙拡張

拡張は `Decl k` のスマートコンストラクタと `meta` を組み合わせて新しい語彙を定義する。

```haskell
module Plat.Ext.DDD where

import Plat.Core

value :: Text -> LayerDef -> DeclWriter 'Model () -> Decl 'Model
value name ly body = model name ly $ do
  meta "plat-ddd:kind" "value"
  body

aggregate :: Text -> LayerDef -> DeclWriter 'Model () -> Decl 'Model
aggregate name ly body = model name ly $ do
  meta "plat-ddd:kind" "aggregate"
  body

invariant :: Text -> Text -> DeclWriter 'Model ()
invariant name expr = meta ("plat-ddd:invariant:" <> name) expr

enum_ :: Text -> LayerDef -> [Text] -> Decl 'Model
enum_ name ly variants = model name ly $ do
  meta "plat-ddd:kind" "enum"
  forM_ variants $ \v -> meta ("plat-ddd:variant:" <> v) v
```

`invariant` の型シグネチャは `DeclWriter 'Model ()` であり、model コンテキストでのみ使用可能である。これは phantom type による自然な制約である。

### 10.3 検証ルールの拡張

```haskell
data ValueNoIdRule = ValueNoIdRule

instance PlatRule ValueNoIdRule where
  ruleCode _ = "DDD-V001"
  checkDecl _ _ decl
    | isValue decl, any isIdField (declBody decl)
    = [Diagnostic Error "DDD-V001"
        "value object must not have an Id field"
        (declName decl) Nothing]
    | otherwise = []

-- ヘルパー
isValue :: Declaration -> Bool
isValue d = declKind d == Model
         && lookup "plat-ddd:kind" (declMeta d) == Just "value"

isIdField :: DeclItem -> Bool
isIdField (Field name _) = T.toLower name == "id"
isIdField _              = False

dddRules :: [SomeRule]
dddRules = [SomeRule ValueNoIdRule, ...]
```

### 10.4 統合

```haskell
let result = checkWith (coreRules ++ dddRules ++ cqrsRules) architecture
```

### 10.5 ユーザー定義拡張

```haskell
module MyOrg.Plat (myKeyword, myOrgRules) where

import Plat.Core
import Plat.Check.Class

myKeyword :: Text -> LayerDef -> DeclWriter 'Model () -> Decl 'Model
myKeyword name ly body = model name ly $ do
  meta "my-org:kind" "my-keyword"
  body

data MyRule = MyRule
instance PlatRule MyRule where ...

myOrgRules :: [SomeRule]
myOrgRules = [SomeRule MyRule]
```

---

## 11. 標準拡張モジュール

標準拡張は `plat-hs` パッケージ内のモジュールとして提供する。パッケージの分割は、需要と安定性を見て将来判断する。

### 11.1 一覧

| モジュール | 主な語彙 |
|----------|---------|
| `Plat.Ext.DDD` | `value`, `enum_`, `aggregate`, `invariant` |
| `Plat.Ext.DBC` | `pre`, `post`, `assert_`, `opWithContract` |
| `Plat.Ext.Flow` | `step`, `policy`, `guard_` |
| `Plat.Ext.Http` | `controller`, `route`, `presenter`, `view_` |
| `Plat.Ext.Events` | `event`, `apply_`, `emit`, `on_` |
| `Plat.Ext.CQRS` | `command`, `query` |
| `Plat.Ext.Modules` | `domain`, `expose`, `import_` |
| `Plat.Ext.CleanArch` | `entity`, `usecase`, `port`, `impl_`, `wire` |

### 11.2 `Plat.Ext.DDD`

```haskell
import Plat.Core
import Plat.Ext.DDD

moneyValue :: Decl 'Model
moneyValue = value "Money" core $ do
  field "amount"   int
  field "currency" string
  invariant "nonNegative" "amount >= 0"

orderStatus :: Decl 'Model
orderStatus = enum_ "OrderStatus" core
  ["draft", "placed", "paid", "shipped", "cancelled"]

order :: Decl 'Model
order = aggregate "Order" core $ do
  field "id"     uuid
  field "items"  (list (ref orderItem))
  field "status" (ref orderStatus)
  field "total"  (ref moneyValue)
```

### 11.3 `Plat.Ext.CQRS`

```haskell
import Plat.Core
import Plat.Ext.CQRS

-- | command は operation + meta タグ
command :: Text -> LayerDef -> DeclWriter 'Operation () -> Decl 'Operation

-- | query は operation + meta タグ
query :: Text -> LayerDef -> DeclWriter 'Operation () -> Decl 'Operation
```

```haskell
placeOrderCmd :: Decl 'Operation
placeOrderCmd = command "PlaceOrder" application $ do
  input  "customerId" uuid
  input  "items"      (list (ref orderItem))
  output "order"      (ref order)
  output "err"        error_
  needs orderRepo

getOrderQuery :: Decl 'Operation
getOrderQuery = query "GetOrder" application $ do
  input  "id"    uuid
  output "order" (ref order)
  output "err"   error_
  needs orderRepo
```

### 11.4 `Plat.Ext.CleanArch`

```haskell
import Plat.Core
import Plat.Ext.CleanArch

-- プリセットレイヤー
enterprise, application, interface, framework :: LayerDef
cleanArchLayers :: [LayerDef]

-- entity は model + meta
entity :: Text -> LayerDef -> DeclWriter 'Model () -> Decl 'Model

-- port は boundary + meta
port :: Text -> LayerDef -> DeclWriter 'Boundary () -> Decl 'Boundary
```

```haskell
orderEntity :: Decl 'Model
orderEntity = entity "Order" enterprise $ do
  field "id"    uuid
  field "total" decimal

orderRepoPort :: Decl 'Boundary
orderRepoPort = port "OrderRepository" interface $ do
  op "save"
    ["order" .: ref orderEntity]
    ["err" .: error_]
```

### 11.5 `Plat.Ext.Http`

```haskell
import Plat.Core
import Plat.Ext.Http

-- | HTTP メソッド
data Method = GET | POST | PUT | DELETE | PATCH

-- | controller は adapter + meta（implements なし）
controller :: Text -> LayerDef -> DeclWriter 'Adapter () -> Decl 'Adapter

-- | route は meta としてルーティング情報を記録
route :: Method -> Text -> Decl 'Operation -> DeclWriter 'Adapter ()
```

`controller` は `adapter` のラッパーであり、`meta "plat-http:kind" "controller"` を付与する。`implements` なしの adapter として扱われる。

`route` は `Decl 'Operation` を値参照し、メソッド・パス・対象 operation をメタデータに記録する。

```haskell
orderHandler :: Decl 'Adapter
orderHandler = controller "OrderController" infra $ do
  path "adapter/http/handler.go"
  route POST   "/orders"       placeOrder
  route DELETE "/orders/{id}"  cancelOrder
  route GET    "/orders/{id}"  getOrder
```

---

## 12. .plat 生成バックエンド

### 12.1 API

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

### 12.2 出力フォーマット

各宣言種の `.plat` 出力構文を以下に示す。

**レイヤー**:
```
layer core
layer application : core
layer interface : core
layer infra : core, application, interface
```

**型エイリアス**:
```
type Money = Decimal
type EmailAddress = String
type OrderItems = List<OrderItem>
```

**カスタム型**（`registerType` で登録された型）:
```
type UUID
type URL
```

**モデル**:
```
model Order : core {
  @ domain/order.go
  id: UUID
  customerId: UUID
  items: List<OrderItem>
  status: OrderStatus
  total: Money
  createdAt: DateTime
  updatedAt: DateTime
}
```

**バウンダリ**:
```
boundary OrderRepository : interface {
  @ usecase/port/order_repo.go
  save: (Order) -> Error
  findById: (UUID) -> (Order, Error)
  findByCustomer: (UUID) -> Stream<Order>
}
```

パラメータ名は `.plat` には含まれない（§12.4 参照）。

**オペレーション**:
```
operation PlaceOrder : application {
  @ usecase/place_order.go
  in customerId: UUID
  in items: List<OrderItem>
  in cardToken: String
  out order: Order
  out err: Error
  needs OrderRepository
  needs PaymentGateway
  needs EventPublisher
}
```

**アダプター（implements あり）**:
```
adapter PostgresOrderRepo : infra implements OrderRepository {
  @ adapter/postgres/order_repo.go
  inject db: *sql.DB
}
```

**アダプター（implements なし）**:
```
adapter OrderHttpHandler : infra {
  @ adapter/http/handler.go
  inject placeOrder: PlaceOrder
  inject cancelOrder: CancelOrder
  inject getOrder: GetOrder
  inject router: chi.Router
}
```

**コンポーズ**:
```
compose AppRoot {
  bind OrderRepository -> PostgresOrderRepo
  bind PaymentGateway -> StripePayment
  bind EventPublisher -> KafkaEventPublisher
  entry OrderHttpHandler
  entry MainServer
}
```

### 12.3 ファイル分割規則

| 宣言の種類 | 出力先 |
|-----------|--------|
| `layer` | `design/layers.plat` |
| `type` | `design/types.plat` |
| `model` | `design/models/{name}.plat` |
| `operation` | `design/operations/{name}.plat` |
| `boundary` | `design/boundaries/{name}.plat` |
| `adapter` | `design/adapters/{name}.plat` |
| `compose` | `design/compose.plat` |

`{name}` はケバブケース変換される（例: `OrderRepository` → `order-repository`）。

### 12.4 名前付きパラメータの .plat 出力

eDSL の名前付きパラメータは `.plat` 生成時に positional に変換される。

```
-- eDSL
op "charge"
  ["amount" .: alias money, "cardToken" .: string]
  ["chargeId" .: string, "err" .: error_]

-- .plat 出力
charge: (Money, String) -> (String, Error)
```

パラメータ名は `.plat` には含まれないが、将来の sync チェックでターゲット言語のシグネチャとの照合に使用される。

### 12.5 メタデータの .plat 出力

`declMeta` に格納されたメタデータは、`.plat` の標準構文には含まれない。拡張パッケージが `.plat` 出力にメタデータを反映する場合は、拡張専用のレンダラーを提供する。

Core の `.plat` レンダラーはメタデータを無視する。これにより、生成された `.plat` は Plat Core 仕様に準拠した標準ファイルとなる。

### 12.6 TypeExpr の .plat 出力

| TypeExpr | .plat 出力 |
|----------|-----------|
| `TBuiltin BString` | `String` |
| `TBuiltin BInt` | `Int` |
| `TBuiltin BFloat` | `Float` |
| `TBuiltin BDecimal` | `Decimal` |
| `TBuiltin BBool` | `Bool` |
| `TBuiltin BUnit` | `Unit` |
| `TBuiltin BBytes` | `Bytes` |
| `TBuiltin BDateTime` | `DateTime` |
| `TBuiltin BAny` | `Any` |
| `TRef name` | `{name}` |
| `TGeneric name [args]` | `{name}<{args}>` |
| `TNullable t` | `{t}?` |

### 12.7 Mermaid / Markdown

```haskell
module Plat.Generate.Mermaid where
renderMermaid :: Architecture -> Text

module Plat.Generate.Markdown where
renderMarkdown :: Architecture -> Text
```

---

## 13. パッケージ構成と利用

### 13.1 Cabal パッケージ

```
plat-hs              -- Core eDSL + 検証 + 生成 + 標準拡張モジュール
```

v0.5 で計画していた拡張ごとの分割パッケージ（plat-hs-ddd, plat-hs-cqrs 等）は、Core の安定化後に需要に応じて分割する。v0.6 では単一パッケージとして提供する。

### 13.2 ユーザープロジェクト

```cabal
cabal-version: 3.0
name:          my-project-design
version:       0.1.0

executable design-check
  main-is:          Main.hs
  hs-source-dirs:   src
  build-depends:
    , base            >= 4.18 && < 5
    , plat-hs         >= 0.6
  default-language: GHC2021
```

### 13.3 Main.hs テンプレート

```haskell
module Main where

import Plat.Core
import Plat.Check
import Plat.Generate.Plat (renderFiles)
import Plat.Ext.DDD (dddRules)
import Plat.Ext.CQRS (cqrsRules)
import Design.Architecture (architecture)

import qualified Data.Text.IO as T
import System.Exit (exitFailure)
import System.Directory (createDirectoryIfMissing)
import System.FilePath (takeDirectory)
import Control.Monad (when, forM_)

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

  putStrLn $ show (length files) ++ " .plat files generated."
```

---

## 14. GHC 要件

**最小**: GHC 9.6 / **推奨**: GHC 9.10 以上

**ユーザーに要求する言語拡張**:

```haskell
{-# LANGUAGE OverloadedStrings #-}
```

型注釈で `Decl 'Model` 等を記述する場合は `DataKinds` が必要だが、型推論により省略可能である。GHC2024（GHC 9.10+）では `DataKinds` が標準で有効。

```haskell
-- GHC2021 + OverloadedStrings: 型注釈なしなら DataKinds 不要
order = model "Order" core $ do ...

-- 型注釈を書く場合は DataKinds が必要（GHC2024 では不要）
{-# LANGUAGE DataKinds #-}
order :: Decl 'Model
order = model "Order" core $ do ...
```

**plat-hs 内部で使用する拡張**: `DataKinds`, `GADTs`（`SomeRule` の存在型）, `OverloadedStrings`, `DerivingStrategies`, `GeneralizedNewtypeDeriving`, `KindSignatures`, `TypeFamilies`（`HasPath`, `Referenceable`）。

---

## 15. 利用例 — Go クリーンアーキテクチャ

Go の EC サイト・オーダー管理サービスを plat-hs で記述する完全な例。

### 15.1 プロジェクト構成

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

### 15.2 Design/Layers.hs

```haskell
module Design.Layers where

import Plat.Core
import Plat.Ext.CleanArch (cleanArchLayers, enterprise, application, interface, framework)

-- CleanArch プリセットを使用
-- enterprise, application, interface, framework が利用可能
```

### 15.3 Design/Models.hs

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Design.Models where

import Plat.Core
import Plat.Ext.DDD
import Design.Layers

uuid :: TypeExpr
uuid = customType "UUID"

orderStatus :: Decl 'Model
orderStatus = enum_ "OrderStatus" enterprise
  ["draft", "placed", "paid", "shipped", "cancelled"]

money :: Decl 'Model
money = value "Money" enterprise $ do
  field "amount"   int
  field "currency" string
  invariant "nonNegative" "amount >= 0"

orderItem :: Decl 'Model
orderItem = value "OrderItem" enterprise $ do
  field "productId" uuid
  field "quantity"  int
  field "unitPrice" (ref money)

order :: Decl 'Model
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

### 15.4 Design/Boundaries.hs

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Design.Boundaries where

import Plat.Core
import Design.Layers
import Design.Models

orderRepo :: Decl 'Boundary
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

paymentGateway :: Decl 'Boundary
paymentGateway = boundary "PaymentGateway" interface $ do
  path "usecase/port/payment.go"
  op "charge"
    ["amount" .: ref money, "cardToken" .: string]
    ["chargeId" .: string, "err" .: error_]

eventPublisher :: Decl 'Boundary
eventPublisher = boundary "EventPublisher" interface $ do
  path "usecase/port/event_pub.go"
  op "publish"
    ["topic" .: string, "payload" .: any_]
    ["err" .: error_]
```

### 15.5 Design/Operations.hs

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Design.Operations where

import Plat.Core
import Plat.Ext.CQRS
import Design.Layers
import Design.Models
import Design.Boundaries

placeOrder :: Decl 'Operation
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

cancelOrder :: Decl 'Operation
cancelOrder = command "CancelOrder" application $ do
  path "usecase/cancel_order.go"
  input  "orderId" uuid
  input  "reason"  string
  output "err"     error_
  needs orderRepo
  needs eventPublisher

getOrder :: Decl 'Operation
getOrder = query "GetOrder" application $ do
  path "usecase/get_order.go"
  input  "id"    uuid
  output "order" (ref order)
  output "err"   error_
  needs orderRepo
```

### 15.6 Design/Adapters.hs

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Design.Adapters where

import Plat.Core
import Plat.Ext.Http
import Design.Layers
import Design.Boundaries
import Design.Operations

postgresOrderRepo :: Decl 'Adapter
postgresOrderRepo = adapter "PostgresOrderRepo" framework $ do
  implements orderRepo
  path "adapter/postgres/order_repo.go"
  inject "db" (ext "*sql.DB")

stripePayment :: Decl 'Adapter
stripePayment = adapter "StripePayment" framework $ do
  implements paymentGateway
  path "adapter/stripe/payment.go"
  inject "client" (ext "*stripe.Client")

kafkaPublisher :: Decl 'Adapter
kafkaPublisher = adapter "KafkaEventPublisher" framework $ do
  implements eventPublisher
  path "adapter/kafka/event_pub.go"
  inject "producer" (ext "*kafka.Producer")

orderHandler :: Decl 'Adapter
orderHandler = controller "OrderController" framework $ do
  path "adapter/http/handler.go"
  route POST   "/orders"       placeOrder
  route DELETE "/orders/{id}"  cancelOrder
  route GET    "/orders/{id}"  getOrder
```

### 15.7 Design/Compose.hs

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Design.Compose where

import Plat.Core
import Design.Boundaries
import Design.Adapters

appRoot :: Decl 'Compose
appRoot = compose "AppRoot" $ do
  bind orderRepo       postgresOrderRepo
  bind paymentGateway  stripePayment
  bind eventPublisher  kafkaPublisher
  entry orderHandler
  entryName "MainServer"
```

### 15.8 Design/Architecture.hs

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

  declare orderStatus
  declare money
  declare orderItem
  declare order

  declare orderRepo
  declare paymentGateway
  declare eventPublisher

  declare placeOrder
  declare cancelOrder
  declare getOrder

  declare postgresOrderRepo
  declare stripePayment
  declare kafkaPublisher
  declare orderHandler

  declare appRoot
```

---

## 16. 利用例 — メタプログラミング

### 16.1 CRUD 一括生成

```haskell
crudBoundary :: Decl 'Model -> LayerDef -> Decl 'Boundary
crudBoundary entity ly =
  boundary (declName (unDecl entity) <> "Repository") ly $ do
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

crudRepos :: [Decl 'Boundary]
crudRepos = map (\e -> crudBoundary e interface)
  [order, user, product_, category, payment_]
```

メタプログラミングで生成した宣言を登録する場合は `declares` を使用する。

```haskell
architecture = arch "my-app" $ do
  useLayers [...]
  -- 個別宣言
  declare order
  declare user
  -- メタプログラミングで生成した宣言
  declares (map decl crudRepos)
```

### 16.2 レイヤーパターンの比較

```haskell
-- レイヤー定義を値として共有する
domainLayer = layer "domain"
appLayer    = layer "app"   `depends` [domainLayer]
infraLayer  = layer "infra" `depends` [domainLayer, appLayer]

hexagonal3 :: [LayerDef]
hexagonal3 = [domainLayer, appLayer, infraLayer]

compareLayouts :: IO ()
compareLayouts = forM_ layouts $ \(name, ls) -> do
  let a = arch "test" $ do
        useLayers ls
        declares sharedDecls
      r = check a
  putStrLn $ name ++ ": " ++ show (length (violations r)) ++ " violations"
  where
    layouts =
      [ ("Hexagonal 3-layer", hexagonal3)
      , ("Clean 4-layer", cleanArchLayers)
      ]
```

### 16.3 adapter 自動ペアリング

```haskell
autoBind :: [(Decl 'Boundary, Decl 'Adapter)] -> DeclWriter 'Compose ()
autoBind pairs = forM_ pairs $ \(bnd, adp) -> bind bnd adp

appRoot :: Decl 'Compose
appRoot = compose "AppRoot" $ do
  autoBind [ (orderRepo,      postgresOrderRepo)
           , (paymentGateway, stripePayment)
           , (eventPublisher, kafkaPublisher)
           ]
  entry orderHandler
```

`autoBind` のペアリストは `(Decl 'Boundary, Decl 'Adapter)` 型であり、boundary と adapter の取り違えはコンパイルエラーとなる。

---

## 17. 将来構想

### 17.1 Template Haskell .plat パーサー

```haskell
$(loadPlat "design/models/order.plat")
-- → order :: Decl 'Model
```

### 17.2 QuickCheck プロパティテスト

```haskell
prop_noCircularDeps :: Architecture -> Property
prop_layerInvariant :: Architecture -> Declaration -> Property
```

### 17.3 ターゲット言語プロファイル

`Plat.Lang.Go`, `Plat.Lang.TypeScript` 等で言語固有の型定数・暗黙パラメータ（context.Context 等）・sync チェックアダプターを提供する。

```haskell
import Plat.Lang.Go (ctx)  -- 将来

orderRepo = boundary "OrderRepository" interface $ do
  op "save"
    [ctx, "order" .: ref order]   -- context.Context を暗黙付与
    ["err" .: error_]
```

### 17.4 Rust ツールチェーンとの統合

plat-hs は `.plat` 生成源、Rust ツールチェーンは `plat sync` を担い、`.plat` をインターフェースとして疎結合に連携する。

### 17.5 `alias` のリネーム検討

§7.2 の `alias :: TypeAlias -> TypeExpr` は、`TypeAlias` 型自体が "alias" であることから名前の重複感がある。`useAlias`, `typeRef`, `aliasRef` 等の候補を将来検討する。

---

*plat-hs は現在 RFC フェーズです。フィードバックを歓迎します。*

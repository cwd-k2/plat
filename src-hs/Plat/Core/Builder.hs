-- | 宣言とアーキテクチャを構築するためのモナディック eDSL。
--
-- 'DeclWriter' で個々の宣言（model, boundary 等）を組み立て、
-- 'ArchBuilder' でそれらをアーキテクチャに束ねる。
--
-- @
-- myArch :: Architecture
-- myArch = arch "order-service" $ do
--   useLayers [enterprise, interface, application]
--   declare orderModel
--   declare orderRepo
--   declare placeOrder
-- @
module Plat.Core.Builder
  ( -- * DeclWriter monad
    DeclWriter
  , HasPath

    -- * Layer constructors
  , layer
  , depends

    -- * Type alias constructors
  , (=:)

    -- * Declaration constructors
  , model
  , boundary
  , operation
  , adapter
  , compose

    -- * DeclWriter combinators — Model
  , field

    -- * DeclWriter combinators — Boundary
  , op
  , op'

    -- * DeclWriter combinators — Operation
  , input
  , output
  , needs

    -- * DeclWriter combinators — Adapter
  , implements
  , inject

    -- * DeclWriter combinators — Compose
  , bind
  , entry
  , entryName

    -- * DeclWriter combinators — Universal
  , path
  , meta

    -- * ArchBuilder monad
  , ArchBuilder
  , arch
  , useLayers
  , useTypes
  , registerType
  , declare
  , declares
  , constrain
  , relate
  ) where

import Data.Text (Text)

import Plat.Core.Types

----------------------------------------------------------------------
-- DeclWriter
----------------------------------------------------------------------

-- | ビルダー内部状態
data DeclBuild = DeclBuild
  { dbItems :: [DeclItem]       -- 逆順で蓄積
  , dbPaths :: [FilePath]       -- 逆順で蓄積
  , dbMeta  :: [(Text, Text)]   -- 逆順で蓄積
  }

emptyBuild :: DeclBuild
emptyBuild = DeclBuild [] [] []

-- | 宣言ビルダーモナド。phantom パラメータ @k@ が使用可能なコンビネータを制約する。
--
-- 例えば 'field' は @DeclWriter ''Model' ()@ でのみ使用可能。
newtype DeclWriter (k :: DeclKind) a = DeclWriter (DeclBuild -> (a, DeclBuild))

instance Functor (DeclWriter k) where
  fmap f (DeclWriter g) = DeclWriter $ \s -> let (a, s') = g s in (f a, s')

instance Applicative (DeclWriter k) where
  pure a = DeclWriter $ \s -> (a, s)
  DeclWriter f <*> DeclWriter g = DeclWriter $ \s ->
    let (ab, s')  = f s
        (a,  s'') = g s'
    in  (ab a, s'')

instance Monad (DeclWriter k) where
  DeclWriter g >>= f = DeclWriter $ \s ->
    let (a, s')          = g s
        DeclWriter h     = f a
    in  h s'

runDeclWriter :: DeclWriter k () -> DeclBuild
runDeclWriter (DeclWriter f) = snd (f emptyBuild)

-- | 内部: DeclItem を追加
addItem :: DeclItem -> DeclWriter k ()
addItem item = DeclWriter $ \s -> ((), s { dbItems = item : dbItems s })

-- | 内部: path を追加
addPath :: FilePath -> DeclWriter k ()
addPath fp = DeclWriter $ \s -> ((), s { dbPaths = fp : dbPaths s })

-- | 内部: meta を追加
addMeta :: Text -> Text -> DeclWriter k ()
addMeta k v = DeclWriter $ \s -> ((), s { dbMeta = (k, v) : dbMeta s })

-- | 内部: DeclBuild から Declaration を構築
buildDecl :: DeclKind -> Text -> Maybe Text -> DeclBuild -> Declaration
buildDecl kind name ly db = Declaration
  { declKind  = kind
  , declName  = name
  , declLayer = ly
  , declPaths = reverse (dbPaths db)
  , declBody  = reverse (dbItems db)
  , declMeta  = reverse (dbMeta db)
  }

----------------------------------------------------------------------
-- HasPath 制約（Compose 以外で path が使える）
----------------------------------------------------------------------

-- | 'path' コンビネータを許可する宣言種の制約。'Compose' 以外の全種で有効。
class HasPath (k :: DeclKind)
instance HasPath 'Model
instance HasPath 'Boundary
instance HasPath 'Operation
instance HasPath 'Adapter

----------------------------------------------------------------------
-- Layer constructors
----------------------------------------------------------------------

-- | レイヤー定義
layer :: Text -> LayerDef
layer name = LayerDef name []

-- | レイヤー依存の宣言
depends :: LayerDef -> [LayerDef] -> LayerDef
depends ly deps = ly { layerDeps = map layerName deps }

----------------------------------------------------------------------
-- Type alias constructors
----------------------------------------------------------------------

-- | 型エイリアス定義
(=:) :: Text -> TypeExpr -> TypeAlias
name =: ty = TypeAlias name ty

infix 5 =:

----------------------------------------------------------------------
-- Declaration constructors
----------------------------------------------------------------------

-- | ドメインモデル（エンティティ / 値オブジェクト）を宣言する。
--
-- @
-- order :: Decl 'Model
-- order = model "Order" enterprise $ do
--   field "id"         (idOf order)
--   field "customerId" string
--   field "total"      (ref money)
-- @
model :: Text -> LayerDef -> DeclWriter 'Model () -> Decl 'Model
model name ly body = Decl (buildDecl Model name (Just (layerName ly)) (runDeclWriter body))

-- | 境界（ポート / インターフェース）を宣言する。
--
-- @
-- orderRepo :: Decl 'Boundary
-- orderRepo = boundary "OrderRepository" interface $ do
--   op "Save" ["order" .: ref order] ["id" .: idOf order]
-- @
boundary :: Text -> LayerDef -> DeclWriter 'Boundary () -> Decl 'Boundary
boundary name ly body = Decl (buildDecl Boundary name (Just (layerName ly)) (runDeclWriter body))

-- | ユースケース（アプリケーションサービス）を宣言する。
--
-- @
-- placeOrder :: Decl 'Operation
-- placeOrder = operation "PlaceOrder" application $ do
--   input  "customerId" string
--   output "orderId"    (idOf order)
--   needs  orderRepo
-- @
operation :: Text -> LayerDef -> DeclWriter 'Operation () -> Decl 'Operation
operation name ly body = Decl (buildDecl Operation name (Just (layerName ly)) (runDeclWriter body))

-- | アダプタ（境界の実装）を宣言する。
--
-- @
-- pgOrderRepo :: Decl 'Adapter
-- pgOrderRepo = adapter "PgOrderRepo" framework $ do
--   implements orderRepo
--   inject "connStr" (ext "string")
-- @
adapter :: Text -> LayerDef -> DeclWriter 'Adapter () -> Decl 'Adapter
adapter name ly body = Decl (buildDecl Adapter name (Just (layerName ly)) (runDeclWriter body))

-- | コンポジションルート（DI / 配線）を宣言する。レイヤーを持たない。
--
-- @
-- root :: Decl 'Compose
-- root = compose "OrderService" $ do
--   bind orderRepo pgOrderRepo
--   entry placeOrder
-- @
compose :: Text -> DeclWriter 'Compose () -> Decl 'Compose
compose name body = Decl (buildDecl Compose name Nothing (runDeclWriter body))

----------------------------------------------------------------------
-- DeclWriter combinators
----------------------------------------------------------------------

-- Model

-- | モデルにフィールドを追加する。名前と型式を指定する。
field :: Text -> TypeExpr -> DeclWriter 'Model ()
field name ty = addItem (Field name ty)

-- Boundary

-- | 境界にオペレーション（メソッドシグネチャ）を追加する。入力・出力パラメータのリストを指定する。
op :: Text -> [Param] -> [Param] -> DeclWriter 'Boundary ()
op name ins outs = addItem (Op name ins outs)

-- | 'op' の簡易版。単一の戻り値型を直接指定する。
op' :: Text -> [Param] -> TypeExpr -> DeclWriter 'Boundary ()
op' name params retType = op name params [Param "_" retType]

-- Operation

-- | オペレーションの入力パラメータを宣言する。
input :: Text -> TypeExpr -> DeclWriter 'Operation ()
input name ty = addItem (Input name ty)

-- | オペレーションの出力（戻り値）を宣言する。
output :: Text -> TypeExpr -> DeclWriter 'Operation ()
output name ty = addItem (Output name ty)

-- | オペレーションが依存する境界を宣言する（依存性注入のポート）。
needs :: Decl 'Boundary -> DeclWriter 'Operation ()
needs (Decl d) = addItem (Needs (declName d))

-- Adapter

-- | アダプタが実装する境界を指定する。アダプタごとに最大1つ。
implements :: Decl 'Boundary -> DeclWriter 'Adapter ()
implements (Decl d) = addItem (Implements (declName d))

-- | アダプタが外部から注入される依存（DB接続文字列等）を宣言する。
-- 型は 'ext' で指定し、W002 検証から除外される。
inject :: Text -> TypeExpr -> DeclWriter 'Adapter ()
inject name ty = addItem (Inject name ty)

-- Compose

-- | 境界とアダプタを結合する（DI バインディング）。
bind :: Decl 'Boundary -> Decl 'Adapter -> DeclWriter 'Compose ()
bind (Decl bnd) (Decl adp) = addItem (Bind (declName bnd) (declName adp))

-- | コンポジションのエントリポイントを登録する。任意の宣言種を指定可能。
entry :: Decl k -> DeclWriter 'Compose ()
entry (Decl d) = addItem (Entry (declName d))

-- | 名前を直接指定してエントリポイントを登録する。
entryName :: Text -> DeclWriter 'Compose ()
entryName name = addItem (Entry name)

-- Universal

-- | 宣言に対応するソースファイルパスを指定する（コード生成で使用）。
path :: HasPath k => FilePath -> DeclWriter k ()
path = addPath

-- | 宣言に任意のメタデータ（キー・値ペア）を付与する。
-- 通常は直接使用せず、'Plat.Core.Meta' の型付きヘルパーを使う。
meta :: Text -> Text -> DeclWriter k ()
meta = addMeta

----------------------------------------------------------------------
-- ArchBuilder
----------------------------------------------------------------------

data ArchBuild = ArchBuild
  { abLayers      :: [LayerDef]
  , abTypes       :: [TypeAlias]
  , abCustomTypes :: [Text]
  , abDecls       :: [Declaration]
  , abConstraints :: [ArchConstraint]
  , abRelations   :: [Relation]
  , abMeta        :: [(Text, Text)]
  }

emptyArchBuild :: ArchBuild
emptyArchBuild = ArchBuild [] [] [] [] [] [] []

-- | アーキテクチャビルダーモナド。レイヤー・型エイリアス・宣言を束ねて 'Architecture' を構築する。
newtype ArchBuilder a = ArchBuilder (ArchBuild -> (a, ArchBuild))

instance Functor ArchBuilder where
  fmap f (ArchBuilder g) = ArchBuilder $ \s -> let (a, s') = g s in (f a, s')

instance Applicative ArchBuilder where
  pure a = ArchBuilder $ \s -> (a, s)
  ArchBuilder f <*> ArchBuilder g = ArchBuilder $ \s ->
    let (ab, s')  = f s
        (a,  s'') = g s'
    in  (ab a, s'')

instance Monad ArchBuilder where
  ArchBuilder g >>= f = ArchBuilder $ \s ->
    let (a, s')          = g s
        ArchBuilder h    = f a
    in  h s'

-- | アーキテクチャを構築する。名前と 'ArchBuilder' ブロックを受け取る。
arch :: Text -> ArchBuilder () -> Architecture
arch name (ArchBuilder f) =
  let ((), ab) = f emptyArchBuild
  in Architecture
    { archName        = name
    , archLayers      = reverse (abLayers ab)
    , archTypes       = reverse (abTypes ab)
    , archCustomTypes = reverse (abCustomTypes ab)
    , archDecls       = reverse (abDecls ab)
    , archConstraints = reverse (abConstraints ab)
    , archRelations   = reverse (abRelations ab)
    , archMeta        = reverse (abMeta ab)
    }

-- | アーキテクチャにレイヤー定義を登録する。依存方向の検証（V001, V002）で使用される。
useLayers :: [LayerDef] -> ArchBuilder ()
useLayers ls = ArchBuilder $ \s -> ((), s { abLayers = reverse ls ++ abLayers s })

-- | 型エイリアスを登録する。W002（未定義型）検証で既知型として扱われる。
useTypes :: [TypeAlias] -> ArchBuilder ()
useTypes ts = ArchBuilder $ \s -> ((), s { abTypes = reverse ts ++ abTypes s })

-- | カスタム型名を登録する。W002 検証で既知型として扱われるが、エイリアス展開はされない。
registerType :: Text -> ArchBuilder ()
registerType t = ArchBuilder $ \s -> ((), s { abCustomTypes = t : abCustomTypes s })

-- | phantom-tagged 宣言を登録する。型タグはここで消去される。
declare :: Decl k -> ArchBuilder ()
declare (Decl d) = ArchBuilder $ \s -> ((), s { abDecls = d : abDecls s })

-- | 複数の untagged 'Declaration' を一括登録する。動的に生成した宣言の注入に使う。
declares :: [Declaration] -> ArchBuilder ()
declares ds = ArchBuilder $ \s -> ((), s { abDecls = reverse ds ++ abDecls s })

-- | アーキテクチャ制約を宣言する。検査関数は違反メッセージのリストを返す。
--
-- @
-- constrain "adapter-has-impl"
--   "every adapter must implement a boundary" $
--   require Adapter "has no implements"
--     (\\d -> isJust (findImplements (declBody d)))
-- @
constrain :: Text -> Text -> (Architecture -> [Text]) -> ArchBuilder ()
constrain name desc chk = ArchBuilder $ \s ->
  ((), s { abConstraints = ArchConstraint name desc chk : abConstraints s })

-- | 宣言間の明示的な関係を登録する。
--
-- DeclItem に含まれない関係（uses, publishes, subscribes 等）を表現する。
-- 'Plat.Core.Relation.relations' で暗黙的関係と統合してクエリできる。
--
-- @
-- relate "uses" getOrder placeOrder
-- relate "publishes" placeOrder orderPlacedEvent
-- @
relate :: Text -> Decl a -> Decl b -> ArchBuilder ()
relate kind (Decl src) (Decl tgt) = ArchBuilder $ \s ->
  ((), s { abRelations = Relation kind (declName src) (declName tgt) [] : abRelations s })

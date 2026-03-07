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

-- | 宣言ビルダーモナド
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

model :: Text -> LayerDef -> DeclWriter 'Model () -> Decl 'Model
model name ly body = Decl (buildDecl Model name (Just (layerName ly)) (runDeclWriter body))

boundary :: Text -> LayerDef -> DeclWriter 'Boundary () -> Decl 'Boundary
boundary name ly body = Decl (buildDecl Boundary name (Just (layerName ly)) (runDeclWriter body))

operation :: Text -> LayerDef -> DeclWriter 'Operation () -> Decl 'Operation
operation name ly body = Decl (buildDecl Operation name (Just (layerName ly)) (runDeclWriter body))

adapter :: Text -> LayerDef -> DeclWriter 'Adapter () -> Decl 'Adapter
adapter name ly body = Decl (buildDecl Adapter name (Just (layerName ly)) (runDeclWriter body))

compose :: Text -> DeclWriter 'Compose () -> Decl 'Compose
compose name body = Decl (buildDecl Compose name Nothing (runDeclWriter body))

----------------------------------------------------------------------
-- DeclWriter combinators
----------------------------------------------------------------------

-- Model

field :: Text -> TypeExpr -> DeclWriter 'Model ()
field name ty = addItem (Field name ty)

-- Boundary

op :: Text -> [Param] -> [Param] -> DeclWriter 'Boundary ()
op name ins outs = addItem (Op name ins outs)

op' :: Text -> [Param] -> TypeExpr -> DeclWriter 'Boundary ()
op' name params retType = op name params [Param "_" retType]

-- Operation

input :: Text -> TypeExpr -> DeclWriter 'Operation ()
input name ty = addItem (Input name ty)

output :: Text -> TypeExpr -> DeclWriter 'Operation ()
output name ty = addItem (Output name ty)

needs :: Decl 'Boundary -> DeclWriter 'Operation ()
needs (Decl d) = addItem (Needs (declName d))

-- Adapter

implements :: Decl 'Boundary -> DeclWriter 'Adapter ()
implements (Decl d) = addItem (Implements (declName d))

inject :: Text -> TypeExpr -> DeclWriter 'Adapter ()
inject name ty = addItem (Inject name ty)

-- Compose

bind :: Decl 'Boundary -> Decl 'Adapter -> DeclWriter 'Compose ()
bind (Decl bnd) (Decl adp) = addItem (Bind (declName bnd) (declName adp))

entry :: Decl k -> DeclWriter 'Compose ()
entry (Decl d) = addItem (Entry (declName d))

entryName :: Text -> DeclWriter 'Compose ()
entryName name = addItem (Entry name)

-- Universal

path :: HasPath k => FilePath -> DeclWriter k ()
path = addPath

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
  , abMeta        :: [(Text, Text)]
  }

emptyArchBuild :: ArchBuild
emptyArchBuild = ArchBuild [] [] [] [] []

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

arch :: Text -> ArchBuilder () -> Architecture
arch name (ArchBuilder f) =
  let ((), ab) = f emptyArchBuild
  in Architecture
    { archName        = name
    , archLayers      = reverse (abLayers ab)
    , archTypes       = reverse (abTypes ab)
    , archCustomTypes = reverse (abCustomTypes ab)
    , archDecls       = reverse (abDecls ab)
    , archMeta        = reverse (abMeta ab)
    }

useLayers :: [LayerDef] -> ArchBuilder ()
useLayers ls = ArchBuilder $ \s -> ((), s { abLayers = reverse ls ++ abLayers s })

useTypes :: [TypeAlias] -> ArchBuilder ()
useTypes ts = ArchBuilder $ \s -> ((), s { abTypes = reverse ts ++ abTypes s })

registerType :: Text -> ArchBuilder ()
registerType t = ArchBuilder $ \s -> ((), s { abCustomTypes = t : abCustomTypes s })

declare :: Decl k -> ArchBuilder ()
declare (Decl d) = ArchBuilder $ \s -> ((), s { abDecls = d : abDecls s })

declares :: [Declaration] -> ArchBuilder ()
declares ds = ArchBuilder $ \s -> ((), s { abDecls = reverse ds ++ abDecls s })

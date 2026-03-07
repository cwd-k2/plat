-- | Architecture manifest for conformance verification.
--
-- Generates a language-agnostic JSON manifest describing the expected
-- structure of an implementation. External tools can compare this
-- against actual source code.
--
-- Uses @aeson@ for correct JSON serialization. Both 'ToJSON' and
-- 'FromJSON' instances are provided for round-trip safety.
module Plat.Verify.Manifest
  ( Manifest (..)
  , ManifestDecl (..)
  , ManifestOp (..)
  , ManifestField (..)
  , ManifestBinding (..)
  , ManifestLayer (..)
  , ManifestTypeAlias (..)
  , ManifestConstraint (..)
  , ManifestRelation (..)
  , manifest
  , renderManifest
  , parseManifest
  ) where

import Data.Aeson (ToJSON(..), FromJSON(..), object, (.=), (.:), (.:?), (.!=), withObject)
import Data.Aeson.Encode.Pretty (encodePretty)
import qualified Data.Aeson as Aeson
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Encoding as TLE

import Plat.Core.Types

----------------------------------------------------------------------
-- Manifest types
----------------------------------------------------------------------

data Manifest = Manifest
  { mVersion     :: Text
  , mName        :: Text
  , mLayers      :: [ManifestLayer]
  , mTypeAliases :: [ManifestTypeAlias]
  , mDecls       :: [ManifestDecl]
  , mBindings    :: [ManifestBinding]
  , mConstraints :: [ManifestConstraint]
  , mRelations   :: [ManifestRelation]
  , mMeta        :: [(Text, Text)]
  } deriving stock (Show, Eq)

data ManifestLayer = ManifestLayer
  { mlName :: Text
  , mlDeps :: [Text]
  } deriving stock (Show, Eq)

data ManifestTypeAlias = ManifestTypeAlias
  { mtaName :: Text
  , mtaType :: Text
  } deriving stock (Show, Eq)

data ManifestDecl = ManifestDecl
  { mdName       :: Text
  , mdKind       :: Text
  , mdLayer      :: Maybe Text
  , mdPaths      :: [FilePath]
  , mdFields     :: [ManifestField]
  , mdOps        :: [ManifestOp]
  , mdInputs     :: [ManifestField]
  , mdOutputs    :: [ManifestField]
  , mdNeeds      :: [Text]
  , mdImplements :: Maybe Text
  , mdInjects    :: [ManifestField]
  , mdEntries    :: [Text]
  , mdMeta       :: [(Text, Text)]
  } deriving stock (Show, Eq)

data ManifestField = ManifestField
  { mfName :: Text
  , mfType :: Text
  } deriving stock (Show, Eq)

data ManifestOp = ManifestOp
  { moName    :: Text
  , moInputs  :: [ManifestField]
  , moOutputs :: [ManifestField]
  } deriving stock (Show, Eq)

data ManifestBinding = ManifestBinding
  { mbBoundary :: Text
  , mbAdapter  :: Text
  } deriving stock (Show, Eq)

data ManifestConstraint = ManifestConstraint
  { mcName :: Text
  , mcDesc :: Text
  } deriving stock (Show, Eq)

data ManifestRelation = ManifestRelation
  { mrKind   :: Text
  , mrSource :: Text
  , mrTarget :: Text
  , mrMeta   :: [(Text, Text)]
  } deriving stock (Show, Eq)

----------------------------------------------------------------------
-- ToJSON
----------------------------------------------------------------------

instance ToJSON Manifest where
  toJSON m = object
    [ "schema_version" .= mVersion m
    , "name"           .= mName m
    , "layers"         .= mLayers m
    , "type_aliases"   .= mTypeAliases m
    , "declarations"   .= mDecls m
    , "bindings"       .= mBindings m
    , "constraints"    .= mConstraints m
    , "relations"      .= mRelations m
    , "meta"           .= metaObject (mMeta m)
    ]

instance ToJSON ManifestLayer where
  toJSON l = object
    [ "name"    .= mlName l
    , "depends" .= mlDeps l
    ]

instance ToJSON ManifestTypeAlias where
  toJSON a = object
    [ "name" .= mtaName a
    , "type" .= mtaType a
    ]

instance ToJSON ManifestDecl where
  toJSON d = object
    [ "name"       .= mdName d
    , "kind"       .= mdKind d
    , "layer"      .= mdLayer d
    , "paths"      .= mdPaths d
    , "fields"     .= mdFields d
    , "ops"        .= mdOps d
    , "inputs"     .= mdInputs d
    , "outputs"    .= mdOutputs d
    , "needs"      .= mdNeeds d
    , "implements" .= mdImplements d
    , "injects"    .= mdInjects d
    , "entries"    .= mdEntries d
    , "meta"       .= metaObject (mdMeta d)
    ]

instance ToJSON ManifestField where
  toJSON f = object
    [ "name" .= mfName f
    , "type" .= mfType f
    ]

instance ToJSON ManifestOp where
  toJSON o = object
    [ "name"    .= moName o
    , "inputs"  .= moInputs o
    , "outputs" .= moOutputs o
    ]

instance ToJSON ManifestBinding where
  toJSON b = object
    [ "boundary" .= mbBoundary b
    , "adapter"  .= mbAdapter b
    ]

instance ToJSON ManifestConstraint where
  toJSON c = object
    [ "name"        .= mcName c
    , "description" .= mcDesc c
    ]

instance ToJSON ManifestRelation where
  toJSON r = object
    [ "kind"   .= mrKind r
    , "source" .= mrSource r
    , "target" .= mrTarget r
    , "meta"   .= metaObject (mrMeta r)
    ]

metaObject :: [(Text, Text)] -> Aeson.Value
metaObject = toJSON . Map.fromList

----------------------------------------------------------------------
-- FromJSON
----------------------------------------------------------------------

instance FromJSON Manifest where
  parseJSON = withObject "Manifest" $ \o -> Manifest
    <$> o .:? "schema_version" .!= "0.5"
    <*> o .:  "name"
    <*> o .:  "layers"
    <*> o .:? "type_aliases" .!= []
    <*> o .:  "declarations"
    <*> o .:? "bindings" .!= []
    <*> o .:? "constraints" .!= []
    <*> o .:? "relations" .!= []
    <*> (Map.toList <$> o .:? "meta" .!= Map.empty)

instance FromJSON ManifestLayer where
  parseJSON = withObject "ManifestLayer" $ \o -> ManifestLayer
    <$> o .: "name"
    <*> o .:? "depends" .!= []

instance FromJSON ManifestTypeAlias where
  parseJSON = withObject "ManifestTypeAlias" $ \o -> ManifestTypeAlias
    <$> o .: "name"
    <*> o .: "type"

instance FromJSON ManifestDecl where
  parseJSON = withObject "ManifestDecl" $ \o -> ManifestDecl
    <$> o .:  "name"
    <*> o .:  "kind"
    <*> o .:? "layer"
    <*> o .:? "paths" .!= []
    <*> o .:? "fields" .!= []
    <*> o .:? "ops" .!= []
    <*> o .:? "inputs" .!= []
    <*> o .:? "outputs" .!= []
    <*> o .:? "needs" .!= []
    <*> o .:? "implements"
    <*> o .:? "injects" .!= []
    <*> o .:? "entries" .!= []
    <*> (Map.toList <$> o .:? "meta" .!= Map.empty)

instance FromJSON ManifestField where
  parseJSON = withObject "ManifestField" $ \o -> ManifestField
    <$> o .: "name"
    <*> o .: "type"

instance FromJSON ManifestOp where
  parseJSON = withObject "ManifestOp" $ \o -> ManifestOp
    <$> o .: "name"
    <*> o .:? "inputs" .!= []
    <*> o .:? "outputs" .!= []

instance FromJSON ManifestBinding where
  parseJSON = withObject "ManifestBinding" $ \o -> ManifestBinding
    <$> o .: "boundary"
    <*> o .: "adapter"

instance FromJSON ManifestConstraint where
  parseJSON = withObject "ManifestConstraint" $ \o -> ManifestConstraint
    <$> o .: "name"
    <*> o .: "description"

instance FromJSON ManifestRelation where
  parseJSON = withObject "ManifestRelation" $ \o -> ManifestRelation
    <$> o .: "kind"
    <*> o .: "source"
    <*> o .: "target"
    <*> (Map.toList <$> o .:? "meta" .!= Map.empty)

----------------------------------------------------------------------
-- Build manifest
----------------------------------------------------------------------

manifest :: Architecture -> Manifest
manifest a = Manifest
  { mVersion     = "0.6"
  , mName        = archName a
  , mLayers      = map toManifestLayer (archLayers a)
  , mTypeAliases = map toManifestTypeAlias (archTypes a)
  , mDecls       = map toManifestDecl (archDecls a)
  , mBindings    = concatMap extractBindings (archDecls a)
  , mConstraints = map toManifestConstraint (archConstraints a)
  , mRelations   = map toManifestRelation (archRelations a)
  , mMeta        = archMeta a
  }

toManifestConstraint :: ArchConstraint -> ManifestConstraint
toManifestConstraint c = ManifestConstraint (acName c) (acDesc c)

toManifestRelation :: Relation -> ManifestRelation
toManifestRelation r = ManifestRelation (relKind r) (relSource r) (relTarget r) (relMeta r)

toManifestLayer :: LayerDef -> ManifestLayer
toManifestLayer ly = ManifestLayer (layerName ly) (layerDeps ly)

toManifestTypeAlias :: TypeAlias -> ManifestTypeAlias
toManifestTypeAlias ta = ManifestTypeAlias (aliasName ta) (renderTE (aliasType ta))

toManifestDecl :: Declaration -> ManifestDecl
toManifestDecl d = ManifestDecl
  { mdName       = declName d
  , mdKind       = kindText (declKind d)
  , mdLayer      = declLayer d
  , mdPaths      = declPaths d
  , mdFields     = [ManifestField n (renderTE t) | Field n t <- declBody d]
  , mdOps        = [ManifestOp n
                      [ManifestField pn (renderTE pt) | Param pn pt <- ins]
                      [ManifestField pn (renderTE pt) | Param pn pt <- outs]
                   | Op n ins outs <- declBody d]
  , mdInputs     = [ManifestField n (renderTE t) | Input n t <- declBody d]
  , mdOutputs    = [ManifestField n (renderTE t) | Output n t <- declBody d]
  , mdNeeds      = declNeeds d
  , mdImplements = findImplements (declBody d)
  , mdInjects    = [ManifestField n (renderTE t) | Inject n t <- declBody d]
  , mdEntries    = [n | Entry n <- declBody d]
  , mdMeta       = declMeta d
  }

extractBindings :: Declaration -> [ManifestBinding]
extractBindings d = [ManifestBinding bnd adp | Bind bnd adp <- declBody d]

kindText :: DeclKind -> Text
kindText Model     = "model"
kindText Boundary  = "boundary"
kindText Operation = "operation"
kindText Adapter   = "adapter"
kindText Compose   = "compose"

----------------------------------------------------------------------
-- Render TypeExpr (language-agnostic)
----------------------------------------------------------------------

renderTE :: TypeExpr -> Text
renderTE (TBuiltin b) = case b of
  BString   -> "String"
  BInt      -> "Int"
  BFloat    -> "Float"
  BDecimal  -> "Decimal"
  BBool     -> "Bool"
  BUnit     -> "Unit"
  BBytes    -> "Bytes"
  BDateTime -> "DateTime"
  BAny      -> "Any"
renderTE (TRef name) = name
renderTE (TGeneric name args) = name <> "<" <> T.intercalate ", " (map renderTE args) <> ">"
renderTE (TNullable t) = renderTE t <> "?"

----------------------------------------------------------------------
-- JSON rendering / parsing
----------------------------------------------------------------------

-- | 'Manifest' を JSON テキストにレンダリングする。
renderManifest :: Manifest -> Text
renderManifest m = TL.toStrict (TLE.decodeUtf8 (encodePretty m)) <> "\n"

-- | JSON テキストから 'Manifest' をパースする。
parseManifest :: Text -> Maybe Manifest
parseManifest t = Aeson.decode (TLE.encodeUtf8 (TL.fromStrict t))

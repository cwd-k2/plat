-- | Architecture manifest for conformance verification.
--
-- Generates a language-agnostic JSON manifest describing the expected
-- structure of an implementation. External tools can compare this
-- against actual source code.
module Plat.Verify.Manifest
  ( Manifest (..)
  , ManifestDecl (..)
  , ManifestOp (..)
  , ManifestField (..)
  , ManifestBinding (..)
  , ManifestLayer (..)
  , manifest
  , renderManifest
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import Plat.Core.Types

----------------------------------------------------------------------
-- Manifest types
----------------------------------------------------------------------

data Manifest = Manifest
  { mName     :: Text
  , mLayers   :: [ManifestLayer]
  , mDecls    :: [ManifestDecl]
  , mBindings :: [ManifestBinding]
  } deriving stock (Show, Eq)

data ManifestLayer = ManifestLayer
  { mlName :: Text
  , mlDeps :: [Text]
  } deriving stock (Show, Eq)

data ManifestDecl = ManifestDecl
  { mdName       :: Text
  , mdKind       :: Text
  , mdLayer      :: Maybe Text
  , mdFields     :: [ManifestField]
  , mdOps        :: [ManifestOp]
  , mdNeeds      :: [Text]
  , mdImplements :: Maybe Text
  , mdInjects    :: [ManifestField]
  , mdEntries    :: [Text]
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

----------------------------------------------------------------------
-- Build manifest
----------------------------------------------------------------------

manifest :: Architecture -> Manifest
manifest arch = Manifest
  { mName     = archName arch
  , mLayers   = map toManifestLayer (archLayers arch)
  , mDecls    = map toManifestDecl (archDecls arch)
  , mBindings = concatMap extractBindings (archDecls arch)
  }

toManifestLayer :: LayerDef -> ManifestLayer
toManifestLayer ly = ManifestLayer (layerName ly) (layerDeps ly)

toManifestDecl :: Declaration -> ManifestDecl
toManifestDecl d = ManifestDecl
  { mdName       = declName d
  , mdKind       = kindText (declKind d)
  , mdLayer      = declLayer d
  , mdFields     = [ManifestField n (renderTE t) | Field n t <- declBody d]
  , mdOps        = [ManifestOp n
                      [ManifestField pn (renderTE pt) | Param pn pt <- ins]
                      [ManifestField pn (renderTE pt) | Param pn pt <- outs]
                   | Op n ins outs <- declBody d]
  , mdNeeds      = declNeeds d
  , mdImplements = findImplements (declBody d)
  , mdInjects    = [ManifestField n (renderTE t) | Inject n t <- declBody d]
  , mdEntries    = [n | Entry n <- declBody d]
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
-- Render manifest as JSON
----------------------------------------------------------------------

renderManifest :: Manifest -> Text
renderManifest m = T.unlines
  [ "{"
  , "  \"name\": " <> jsonStr (mName m) <> ","
  , "  \"layers\": ["
  , T.intercalate ",\n" (map renderLayer (mLayers m))
  , "  ],"
  , "  \"declarations\": ["
  , T.intercalate ",\n" (map renderDecl (mDecls m))
  , "  ],"
  , "  \"bindings\": ["
  , T.intercalate ",\n" (map renderBinding (mBindings m))
  , "  ]"
  , "}"
  ]

renderLayer :: ManifestLayer -> Text
renderLayer ly = "    { \"name\": " <> jsonStr (mlName ly)
  <> ", \"depends\": [" <> T.intercalate ", " (map jsonStr (mlDeps ly)) <> "] }"

renderDecl :: ManifestDecl -> Text
renderDecl d = T.unlines
  [ "    {"
  , "      \"name\": " <> jsonStr (mdName d) <> ","
  , "      \"kind\": " <> jsonStr (mdKind d) <> ","
  , "      \"layer\": " <> maybe "null" jsonStr (mdLayer d) <> ","
  , "      \"fields\": [" <> T.intercalate ", " (map renderField (mdFields d)) <> "],"
  , "      \"ops\": [" <> T.intercalate ", " (map renderOp (mdOps d)) <> "],"
  , "      \"needs\": [" <> T.intercalate ", " (map jsonStr (mdNeeds d)) <> "],"
  , "      \"implements\": " <> maybe "null" jsonStr (mdImplements d) <> ","
  , "      \"injects\": [" <> T.intercalate ", " (map renderField (mdInjects d)) <> "],"
  , "      \"entries\": [" <> T.intercalate ", " (map jsonStr (mdEntries d)) <> "]"
  , "    }"
  ]

renderField :: ManifestField -> Text
renderField f = "{\"name\": " <> jsonStr (mfName f) <> ", \"type\": " <> jsonStr (mfType f) <> "}"

renderOp :: ManifestOp -> Text
renderOp o = "{\"name\": " <> jsonStr (moName o)
  <> ", \"inputs\": [" <> T.intercalate ", " (map renderField (moInputs o))
  <> "], \"outputs\": [" <> T.intercalate ", " (map renderField (moOutputs o)) <> "]}"

renderBinding :: ManifestBinding -> Text
renderBinding b = "    {\"boundary\": " <> jsonStr (mbBoundary b)
  <> ", \"adapter\": " <> jsonStr (mbAdapter b) <> "}"

jsonStr :: Text -> Text
jsonStr t = "\"" <> T.concatMap escape t <> "\""
  where
    escape '"'  = "\\\""
    escape '\\' = "\\\\"
    escape '\n' = "\\n"
    escape c    = T.singleton c

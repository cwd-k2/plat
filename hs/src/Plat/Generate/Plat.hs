-- | .plat ファイル生成
module Plat.Generate.Plat
  ( render
  , renderFiles
  , RenderConfig (..)
  , defaultConfig
  , renderWith
  , renderTypeExpr
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Char (toLower, isUpper)

import Plat.Core.Types

-- | 設定
data RenderConfig = RenderConfig
  { rcSplitFiles :: Bool
  , rcDesignDir  :: FilePath
  }

defaultConfig :: RenderConfig
defaultConfig = RenderConfig True "design"

-- | 単一テキストとしてレンダリング
render :: Architecture -> Text
render arch = T.intercalate "\n\n" $
  [ renderLayers (archLayers arch) | not (null (archLayers arch)) ]
  ++ [ renderTypes (archTypes arch) (archCustomTypes arch)
     | not (null (archTypes arch)) || not (null (archCustomTypes arch)) ]
  ++ map renderDecl (archDecls arch)

-- | ファイル分割してレンダリング
renderFiles :: Architecture -> [(FilePath, Text)]
renderFiles = renderWith defaultConfig

-- | 設定付きレンダリング
renderWith :: RenderConfig -> Architecture -> [(FilePath, Text)]
renderWith cfg arch
  | not (rcSplitFiles cfg) = [(rcDesignDir cfg <> "/architecture.plat", render arch)]
  | otherwise = filter (not . T.null . snd) $
      [ (dir <> "/layers.plat", renderLayers (archLayers arch)) ]
      ++ [ (dir <> "/types.plat", renderTypes (archTypes arch) (archCustomTypes arch))
         | not (null (archTypes arch)) || not (null (archCustomTypes arch)) ]
      ++ concatMap (declToFile dir) (archDecls arch)
  where dir = rcDesignDir cfg

declToFile :: FilePath -> Declaration -> [(FilePath, Text)]
declToFile dir d = [(filePath, renderDecl d)]
  where
    kebab = toKebabCase (declName d)
    filePath = case declKind d of
      Model     -> dir <> "/models/" <> kebab <> ".plat"
      Boundary  -> dir <> "/boundaries/" <> kebab <> ".plat"
      Operation -> dir <> "/operations/" <> kebab <> ".plat"
      Adapter   -> dir <> "/adapters/" <> kebab <> ".plat"
      Compose   -> dir <> "/compose.plat"

----------------------------------------------------------------------
-- Rendering
----------------------------------------------------------------------

renderLayers :: [LayerDef] -> Text
renderLayers = T.intercalate "\n" . map renderLayer

renderLayer :: LayerDef -> Text
renderLayer l
  | null (layerDeps l) = "layer " <> layerName l
  | otherwise = "layer " <> layerName l <> " : " <> T.intercalate ", " (layerDeps l)

renderTypes :: [TypeAlias] -> [Text] -> Text
renderTypes aliases customs = T.intercalate "\n" $
  map renderAlias aliases ++ map renderCustom customs

renderAlias :: TypeAlias -> Text
renderAlias ta = "type " <> aliasName ta <> " = " <> renderTypeExpr (aliasType ta)

renderCustom :: Text -> Text
renderCustom name = "type " <> name

renderDecl :: Declaration -> Text
renderDecl d = case declKind d of
  Model     -> renderBlock "model"     d (map renderField (declFields d))
  Boundary  -> renderBlock "boundary"  d (map renderOp (declOps d))
  Operation -> renderBlock "operation" d (renderOpBody d)
  Adapter   -> renderAdapterBlock d
  Compose   -> renderComposeBlock d

renderBlock :: Text -> Declaration -> [Text] -> Text
renderBlock kw d bodyLines =
  kw <> " " <> declName d <> layerSuffix d <> " {\n"
  <> T.unlines (map ("  " <>) (pathLines d ++ bodyLines))
  <> "}"

layerSuffix :: Declaration -> Text
layerSuffix d = case declLayer d of
  Just l  -> " : " <> l
  Nothing -> ""

pathLines :: Declaration -> [Text]
pathLines d = ["@ " <> T.pack fp | fp <- declPaths d]

renderField :: (Text, TypeExpr) -> Text
renderField (name, ty) = name <> ": " <> renderTypeExpr ty

renderOp :: (Text, [Param], [Param]) -> Text
renderOp (name, ins, outs) =
  name <> ": " <> renderParams ins <> " -> " <> renderParams outs

renderParams :: [Param] -> Text
renderParams []  = "()"
renderParams [p] = renderTypeExpr (paramType p)
renderParams ps  = "(" <> T.intercalate ", " (map (renderTypeExpr . paramType) ps) <> ")"

renderOpBody :: Declaration -> [Text]
renderOpBody d =
  ["in " <> name <> ": " <> renderTypeExpr ty | Input name ty <- declBody d]
  ++ ["out " <> name <> ": " <> renderTypeExpr ty | Output name ty <- declBody d]
  ++ ["needs " <> name | Needs name <- declBody d]

renderAdapterBlock :: Declaration -> Text
renderAdapterBlock d =
  "adapter " <> declName d <> layerSuffix d <> implSuffix <> " {\n"
  <> T.unlines (map ("  " <>) (pathLines d ++ bodyLines))
  <> "}"
  where
    implSuffix = case findImplements (declBody d) of
      Just bnd -> " implements " <> bnd
      Nothing  -> ""
    bodyLines =
      ["inject " <> name <> ": " <> renderTypeExpr ty | Inject name ty <- declBody d]

renderComposeBlock :: Declaration -> Text
renderComposeBlock d =
  "compose " <> declName d <> " {\n"
  <> T.unlines (map ("  " <>) bodyLines)
  <> "}"
  where
    bodyLines =
      ["bind " <> bnd <> " -> " <> adp | Bind bnd adp <- declBody d]
      ++ ["entry " <> name | Entry name <- declBody d]

----------------------------------------------------------------------
-- TypeExpr rendering
----------------------------------------------------------------------

renderTypeExpr :: TypeExpr -> Text
renderTypeExpr (TBuiltin b)     = renderBuiltin b
renderTypeExpr (TRef name)      = name
renderTypeExpr (TGeneric name args) =
  name <> "<" <> T.intercalate ", " (map renderTypeExpr args) <> ">"
renderTypeExpr (TNullable t)    = renderTypeExpr t <> "?"

renderBuiltin :: Builtin -> Text
renderBuiltin BString   = "String"
renderBuiltin BInt      = "Int"
renderBuiltin BFloat    = "Float"
renderBuiltin BDecimal  = "Decimal"
renderBuiltin BBool     = "Bool"
renderBuiltin BUnit     = "Unit"
renderBuiltin BBytes    = "Bytes"
renderBuiltin BDateTime = "DateTime"
renderBuiltin BAny      = "Any"

----------------------------------------------------------------------
-- Utilities
----------------------------------------------------------------------

-- | PascalCase → kebab-case
toKebabCase :: Text -> String
toKebabCase t = case T.unpack t of
  []     -> []
  (c:cs) -> toLower c : go cs
  where
    go [] = []
    go (c:cs)
      | isUpper c = '-' : toLower c : go cs
      | otherwise = c : go cs

-- | Markdown ドキュメント生成
module Plat.Generate.Markdown
  ( renderMarkdown
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import Plat.Core.Types
import Plat.Generate.Plat (renderTypeExpr)

-- | Architecture から Markdown ドキュメントを生成
renderMarkdown :: Architecture -> Text
renderMarkdown arch = T.unlines $
  [ "# " <> archName arch
  , ""
  ]
  ++ renderLayerSection (archLayers arch)
  ++ concatMap (renderDeclSection arch) (archDecls arch)

renderLayerSection :: [LayerDef] -> [Text]
renderLayerSection [] = []
renderLayerSection ls =
  [ "## Layers", "" ]
  ++ [ "| Layer | Dependencies |"
     , "|-------|-------------|"
     ]
  ++ map renderLayerRow ls
  ++ [""]

renderLayerRow :: LayerDef -> Text
renderLayerRow l
  | null (layerDeps l) = "| " <> layerName l <> " | — |"
  | otherwise = "| " <> layerName l <> " | " <> T.intercalate ", " (layerDeps l) <> " |"

renderDeclSection :: Architecture -> Declaration -> [Text]
renderDeclSection _ d = case declKind d of
  Model     -> renderModelSection d
  Boundary  -> renderBoundarySection d
  Operation -> renderOperationSection d
  Adapter   -> renderAdapterSection d
  Compose   -> renderComposeSection d

renderModelSection :: Declaration -> [Text]
renderModelSection d =
  [ "## " <> declName d
  , ""
  , "**Kind**: Model" <> layerNote d
  , ""
  ]
  ++ pathNotes d
  ++ case declFields d of
    [] -> []
    fs ->
      [ "| Field | Type |"
      , "|-------|------|"
      ]
      ++ [ "| " <> n <> " | `" <> renderTypeExpr t <> "` |" | (n, t) <- fs ]
      ++ [""]

renderBoundarySection :: Declaration -> [Text]
renderBoundarySection d =
  [ "## " <> declName d
  , ""
  , "**Kind**: Boundary" <> layerNote d
  , ""
  ]
  ++ pathNotes d
  ++ case declOps d of
    [] -> []
    ops ->
      [ "| Operation | Input | Output |"
      , "|-----------|-------|--------|"
      ]
      ++ [ "| " <> n <> " | " <> renderParamList ins <> " | " <> renderParamList outs <> " |"
         | (n, ins, outs) <- ops ]
      ++ [""]

renderOperationSection :: Declaration -> [Text]
renderOperationSection d =
  [ "## " <> declName d
  , ""
  , "**Kind**: Operation" <> layerNote d
  , ""
  ]
  ++ pathNotes d
  ++ inputOutput d
  ++ case declNeeds d of
    [] -> []
    ns -> ["**Depends on**: " <> T.intercalate ", " ns, ""]

renderAdapterSection :: Declaration -> [Text]
renderAdapterSection d =
  [ "## " <> declName d
  , ""
  , "**Kind**: Adapter" <> layerNote d
  ]
  ++ maybe [] (\b -> ["", "**Implements**: " <> b]) (findImplements (declBody d))
  ++ [""]
  ++ pathNotes d
  ++ case [(n, t) | Inject n t <- declBody d] of
    [] -> []
    is ->
      [ "| Injection | Type |"
      , "|-----------|------|"
      ]
      ++ [ "| " <> n <> " | `" <> renderTypeExpr t <> "` |" | (n, t) <- is ]
      ++ [""]

renderComposeSection :: Declaration -> [Text]
renderComposeSection d =
  [ "## " <> declName d
  , ""
  , "**Kind**: Compose"
  , ""
  ]
  ++ case [(b, a) | Bind b a <- declBody d] of
    [] -> []
    bs ->
      [ "| Boundary | Adapter |"
      , "|----------|---------|"
      ]
      ++ [ "| " <> b <> " | " <> a <> " |" | (b, a) <- bs ]
      ++ [""]
  ++ case [n | Entry n <- declBody d] of
    [] -> []
    es -> ["**Entry points**: " <> T.intercalate ", " es, ""]

-- Helpers

layerNote :: Declaration -> Text
layerNote d = case declLayer d of
  Just l  -> " (`" <> l <> "`)"
  Nothing -> ""

pathNotes :: Declaration -> [Text]
pathNotes d = case declPaths d of
  [] -> []
  ps -> ["**Path**: " <> T.intercalate ", " (map (\p -> "`" <> T.pack p <> "`") ps), ""]

inputOutput :: Declaration -> [Text]
inputOutput d =
  let ins  = [(n, t) | Input n t <- declBody d]
      outs = [(n, t) | Output n t <- declBody d]
  in case (ins, outs) of
    ([], []) -> []
    _        ->
      [ "| Direction | Name | Type |"
      , "|-----------|------|------|"
      ]
      ++ [ "| in | " <> n <> " | `" <> renderTypeExpr t <> "` |" | (n, t) <- ins ]
      ++ [ "| out | " <> n <> " | `" <> renderTypeExpr t <> "` |" | (n, t) <- outs ]
      ++ [""]

renderParamList :: [Param] -> Text
renderParamList [] = "—"
renderParamList ps = T.intercalate ", " [ "`" <> renderTypeExpr (paramType p) <> "`" | p <- ps ]

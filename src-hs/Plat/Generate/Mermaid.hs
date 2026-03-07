-- | Mermaid 図生成
module Plat.Generate.Mermaid
  ( renderMermaid
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Maybe (mapMaybe)

import Plat.Core.Types

-- | Architecture から Mermaid flowchart を生成
renderMermaid :: Architecture -> Text
renderMermaid arch = T.unlines $
  ["graph TD"]
  ++ concatMap (renderDeclNode arch) (archDecls arch)
  ++ renderEdges arch

renderDeclNode :: Architecture -> Declaration -> [Text]
renderDeclNode _ d =
  [ "  " <> ident <> shape (declKind d) (declName d) ]
  where
    ident = sanitize (declName d)

    shape Model     name = "[" <> name <> "]"
    shape Boundary  name = "([" <> name <> "])"
    shape Operation name = "[[" <> name <> "]]"
    shape Adapter   name = "[/" <> name <> "/]"
    shape Compose   name = "{{" <> name <> "}}"

renderEdges :: Architecture -> [Text]
renderEdges arch = concatMap (declEdges declMap) (archDecls arch)
  where
    declMap = [(declName d, d) | d <- archDecls arch]

declEdges :: [(Text, Declaration)] -> Declaration -> [Text]
declEdges declMap d = case declKind d of
  Operation ->
    -- needs edges
    [ "  " <> me <> " -.->|needs| " <> sanitize target
    | Needs target <- declBody d
    ]
  Adapter ->
    -- implements edge
    mapMaybe (\case
      Implements target -> Just ("  " <> me <> " -->|implements| " <> sanitize target)
      _                 -> Nothing
    ) (declBody d)
    ++
    -- inject edges (only to known declarations)
    [ "  " <> me <> " -.->|inject| " <> sanitize name
    | Inject _ (TRef name) <- declBody d
    , name `elem` map fst declMap
    ]
  Compose ->
    -- bind edges
    [ "  " <> sanitize bnd <> " ===>|bind| " <> sanitize adp
    | Bind bnd adp <- declBody d
    ]
    ++
    -- entry edges
    [ "  " <> me <> " -->|entry| " <> sanitize name
    | Entry name <- declBody d
    , name `elem` map fst declMap
    ]
  _ -> []
  where
    me = sanitize (declName d)

-- | Mermaid ノード ID に使える形にサニタイズ（英数字とアンダースコアのみ残す）
sanitize :: Text -> Text
sanitize = T.filter (\c -> c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_']))

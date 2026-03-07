-- | HTTP extension: controller, route
module Plat.Ext.Http
  ( Method (..)
  , controller
  , route
  , httpRules
  -- * Meta vocabulary
  , http
  , httpController
  ) where

import Data.Text (Text)

import Plat.Core.Types
import Plat.Core.Builder
import Plat.Core.Meta
import Plat.Check.Class

-- | HTTP method
data Method = GET | POST | PUT | DELETE | PATCH
  deriving stock (Show, Eq, Ord)

renderMethod :: Method -> Text
renderMethod GET    = "GET"
renderMethod POST   = "POST"
renderMethod PUT    = "PUT"
renderMethod DELETE = "DELETE"
renderMethod PATCH  = "PATCH"

-- | HTTP extension identifier
http :: ExtId
http = extId "http"

-- | HTTP コントローラーのメタタグ
httpController :: MetaTag
httpController = kind http "controller"

-- | Controller (adapter without implements)
controller :: Text -> LayerDef -> DeclWriter 'Adapter () -> Decl 'Adapter
controller name ly body = adapter name ly $ do
  tagAs httpController
  body

-- | Route (records method, path, and target operation as metadata)
route :: Method -> Text -> Decl 'Operation -> DeclWriter 'Adapter ()
route method routePath target = do
  let opName = declName (unDecl target)
  annotate http "route" opName (renderMethod method <> " " <> routePath)
  inject opName (TRef opName)

----------------------------------------------------------------------
-- HTTP Rules
----------------------------------------------------------------------

-- | HTTP-W001: controller タグ付き adapter にルートがないこと
data ControllerNoRoutesRule = ControllerNoRoutesRule
instance PlatRule ControllerNoRoutesRule where
  ruleCode _ = "HTTP-W001"
  checkDecl _ _ d
    | isTagged httpController d
    , null (annotations http "route" d)
    = [ Diagnostic Warning "HTTP-W001"
          ("controller " <> declName d <> " has no routes defined")
          (declName d) Nothing
      ]
    | otherwise = []

-- | HTTP 拡張の検証ルール一覧
httpRules :: [SomeRule]
httpRules =
  [ SomeRule ControllerNoRoutesRule
  ]

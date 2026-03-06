-- | HTTP 拡張: controller, route
module Plat.Ext.Http
  ( Method (..)
  , controller
  , route
  ) where

import Data.Text (Text)

import Plat.Core.Types
import Plat.Core.Builder

-- | HTTP メソッド
data Method = GET | POST | PUT | DELETE | PATCH
  deriving stock (Show, Eq, Ord)

renderMethod :: Method -> Text
renderMethod GET    = "GET"
renderMethod POST   = "POST"
renderMethod PUT    = "PUT"
renderMethod DELETE = "DELETE"
renderMethod PATCH  = "PATCH"

-- | Controller (adapter without implements)
controller :: Text -> LayerDef -> DeclWriter 'Adapter () -> Decl 'Adapter
controller name ly body = adapter name ly $ do
  meta "plat-http:kind" "controller"
  body

-- | Route (records method, path, and target operation as metadata)
route :: Method -> Text -> Decl 'Operation -> DeclWriter 'Adapter ()
route method routePath target = do
  let opName = declName (unDecl target)
      key = "plat-http:route:" <> opName
      val = renderMethod method <> " " <> routePath
  meta key val
  inject opName (TRef opName)

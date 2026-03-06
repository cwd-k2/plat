-- | Clean Architecture プリセット
module Plat.Ext.CleanArch
  ( -- * Preset layers
    enterprise
  , application
  , interface
  , framework
  , cleanArchLayers

    -- * Smart constructors
  , entity
  , usecase
  , port
  , impl_
  , wire
  ) where

import Data.Text (Text)

import Plat.Core.Types
import Plat.Core.Builder

----------------------------------------------------------------------
-- Preset layers
----------------------------------------------------------------------

enterprise, application, interface, framework :: LayerDef

enterprise  = layer "enterprise"
interface   = layer "interface"   `depends` [enterprise]
application = layer "application" `depends` [enterprise, interface]
framework   = layer "framework"   `depends` [enterprise, interface, application]

cleanArchLayers :: [LayerDef]
cleanArchLayers = [enterprise, application, interface, framework]

----------------------------------------------------------------------
-- Smart constructors
----------------------------------------------------------------------

-- | Entity (model in enterprise layer)
entity :: Text -> LayerDef -> DeclWriter 'Model () -> Decl 'Model
entity name ly body = model name ly $ do
  meta "plat-cleanarch:kind" "entity"
  body

-- | Use case (operation)
usecase :: Text -> LayerDef -> DeclWriter 'Operation () -> Decl 'Operation
usecase name ly body = operation name ly $ do
  meta "plat-cleanarch:kind" "usecase"
  body

-- | Port (boundary)
port :: Text -> LayerDef -> DeclWriter 'Boundary () -> Decl 'Boundary
port name ly body = boundary name ly $ do
  meta "plat-cleanarch:kind" "port"
  body

-- | Implementation (adapter with implements)
impl_ :: Text -> LayerDef -> Decl 'Boundary -> DeclWriter 'Adapter () -> Decl 'Adapter
impl_ name ly bnd body = adapter name ly $ do
  meta "plat-cleanarch:kind" "impl"
  implements bnd
  body

-- | Wire (compose)
wire :: Text -> DeclWriter 'Compose () -> Decl 'Compose
wire name body = compose name $ do
  meta "plat-cleanarch:kind" "wire"
  body

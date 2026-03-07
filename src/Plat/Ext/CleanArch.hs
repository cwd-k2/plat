-- | Clean Architecture preset
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

    -- * Meta vocabulary
  , cleanArch
  , caEntity
  , caUsecase
  , caPort
  , caImpl
  , caWire
  ) where

import Data.Text (Text)

import Plat.Core.Types
import Plat.Core.Builder
import Plat.Core.Meta

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
-- Meta vocabulary
----------------------------------------------------------------------

-- | CleanArch extension identifier
cleanArch :: ExtId
cleanArch = extId "cleanarch"

caEntity, caUsecase, caPort, caImpl, caWire :: MetaTag
caEntity  = kind cleanArch "entity"
caUsecase = kind cleanArch "usecase"
caPort    = kind cleanArch "port"
caImpl    = kind cleanArch "impl"
caWire    = kind cleanArch "wire"

----------------------------------------------------------------------
-- Smart constructors
----------------------------------------------------------------------

-- | Entity (model in enterprise layer)
entity :: Text -> LayerDef -> DeclWriter 'Model () -> Decl 'Model
entity name ly body = model name ly $ do
  tagAs caEntity
  body

-- | Use case (operation)
usecase :: Text -> LayerDef -> DeclWriter 'Operation () -> Decl 'Operation
usecase name ly body = operation name ly $ do
  tagAs caUsecase
  body

-- | Port (boundary)
port :: Text -> LayerDef -> DeclWriter 'Boundary () -> Decl 'Boundary
port name ly body = boundary name ly $ do
  tagAs caPort
  body

-- | Implementation (adapter with implements)
impl_ :: Text -> LayerDef -> Decl 'Boundary -> DeclWriter 'Adapter () -> Decl 'Adapter
impl_ name ly bnd body = adapter name ly $ do
  tagAs caImpl
  implements bnd
  body

-- | Wire (compose)
wire :: Text -> DeclWriter 'Compose () -> Decl 'Compose
wire name body = compose name $ do
  tagAs caWire
  body

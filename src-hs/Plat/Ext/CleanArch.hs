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
  , impl
  , wire

    -- * Rules
  , cleanArchRules

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
import Plat.Check.Class

----------------------------------------------------------------------
-- Preset layers
----------------------------------------------------------------------

-- | Clean Architecture の4レイヤー定義 (enterprise → interface → application → framework)
enterprise, application, interface, framework :: LayerDef

enterprise  = layer "enterprise"
interface   = layer "interface"   `depends` [enterprise]
application = layer "application" `depends` [enterprise, interface]
framework   = layer "framework"   `depends` [enterprise, interface, application]

-- | 全レイヤーのリスト
cleanArchLayers :: [LayerDef]
cleanArchLayers = [enterprise, application, interface, framework]

----------------------------------------------------------------------
-- Meta vocabulary
----------------------------------------------------------------------

-- | CleanArch extension identifier
cleanArch :: ExtId
cleanArch = extId "cleanarch"

-- | CleanArch メタタグ: entity / usecase / port / impl / wire
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
impl :: Text -> LayerDef -> Decl 'Boundary -> DeclWriter 'Adapter () -> Decl 'Adapter
impl name ly bnd body = adapter name ly $ do
  tagAs caImpl
  implements bnd
  body

-- | Wire (compose)
wire :: Text -> DeclWriter 'Compose () -> Decl 'Compose
wire name body = compose name $ do
  tagAs caWire
  body

----------------------------------------------------------------------
-- CleanArch Rules
----------------------------------------------------------------------

-- | CA-V001: impl タグ付き adapter は implements を持つこと
data ImplNeedsImplementsRule = ImplNeedsImplementsRule
instance PlatRule ImplNeedsImplementsRule where
  ruleCode _ = "CA-V001"
  checkDecl _ _ d
    | declKind d == Adapter
    , isTagged caImpl d
    , Nothing <- findImplements (declBody d)
    = [ Diagnostic Error "CA-V001"
          ("clean architecture impl " <> declName d <> " must have implements")
          (declName d) Nothing
      ]
    | otherwise = []

-- | CA-W001: wire タグ付き compose に bind がないこと
data WireNoBindsRule = WireNoBindsRule
instance PlatRule WireNoBindsRule where
  ruleCode _ = "CA-W001"
  checkDecl _ _ d
    | declKind d == Compose
    , isTagged caWire d
    , null [() | Bind _ _ <- declBody d]
    = [ Diagnostic Warning "CA-W001"
          ("clean architecture wire " <> declName d <> " has no bindings")
          (declName d) Nothing
      ]
    | otherwise = []

-- | CleanArch 拡張の検証ルール一覧
cleanArchRules :: [SomeRule]
cleanArchRules =
  [ SomeRule ImplNeedsImplementsRule
  , SomeRule WireNoBindsRule
  ]

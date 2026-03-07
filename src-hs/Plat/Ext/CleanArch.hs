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
import qualified Data.Map.Strict as Map

import Plat.Core.Types
import Plat.Core.Builder
import Plat.Core.Meta
import Plat.Core.Relation (relations)
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

-- | CA-V002: enterprise/interface レイヤーの宣言が framework/application レイヤーの
-- 宣言を参照していないことを検査する (依存性ルール違反)。
data InwardDependencyRule = InwardDependencyRule
instance PlatRule InwardDependencyRule where
  ruleCode _ = "CA-V002"
  checkArch _ a =
    [ Diagnostic Error "CA-V002"
        (src <> " (" <> srcLayer <> ") references " <> tgt <> " (" <> tgtLayer <> ")")
        src Nothing
    | r <- relations a
    , relKind r `elem` ["needs", "references"]
    , let src = relSource r
    , let tgt = relTarget r
    , let srcLayer = Map.findWithDefault "" src layerMap
    , let tgtLayer = Map.findWithDefault "" tgt layerMap
    , isInner srcLayer
    , isOuter tgtLayer
    ]
    where
      layerMap = Map.fromList
        [ (declName d, ly)
        | d <- archDecls a
        , Just ly <- [declLayer d]
        ]
      innerLayers = ["enterprise", "interface"]
      outerLayers = ["framework", "application"]
      isInner ly = ly `elem` innerLayers
      isOuter ly = ly `elem` outerLayers

-- | CleanArch 拡張の検証ルール一覧
cleanArchRules :: [SomeRule]
cleanArchRules =
  [ SomeRule ImplNeedsImplementsRule
  , SomeRule WireNoBindsRule
  , SomeRule InwardDependencyRule
  ]

-- | Flow extension: step, policy, guard_
module Plat.Ext.Flow
  ( step
  , policy
  , guard_
  , flowRules
  -- * Meta vocabulary
  , flow
  , flowStep
  , flowPolicy
  , flowProjection
  ) where

import Data.Text (Text)

import Plat.Core.Types
import Plat.Core.Builder
import Plat.Core.Meta
import Plat.Check.Class

-- | Flow extension identifier
flow :: ExtId
flow = extId "flow"

flowStep, flowPolicy, flowProjection :: MetaTag
flowStep       = kind flow "step"
flowPolicy     = kind flow "policy"
flowProjection = kind flow "projection"

-- | Workflow step (operation)
step :: Text -> LayerDef -> DeclWriter 'Operation () -> Decl 'Operation
step name ly body = operation name ly $ do
  tagAs flowStep
  body

-- | Business policy (model: set of rules/constraints)
policy :: Text -> LayerDef -> DeclWriter 'Model () -> Decl 'Model
policy name ly body = model name ly $ do
  tagAs flowPolicy
  body

-- | Guard condition (operation context)
guard_ :: Text -> Text -> DeclWriter 'Operation ()
guard_ name condition = annotate flow "guard" name condition

flowRules :: [SomeRule]
flowRules = []

-- | Flow 拡張: step, policy, guard_
module Plat.Ext.Flow
  ( step
  , policy
  , guard_
  , flowRules
  ) where

import Data.Text (Text)

import Plat.Core.Types
import Plat.Core.Builder
import Plat.Check.Class

-- | ワークフローのステップ（operation として表現）
step :: Text -> LayerDef -> DeclWriter 'Operation () -> Decl 'Operation
step name ly body = operation name ly $ do
  meta "plat-flow:kind" "step"
  body

-- | ビジネスポリシー（model として表現: ルール/制約の集合）
policy :: Text -> LayerDef -> DeclWriter 'Model () -> Decl 'Model
policy name ly body = model name ly $ do
  meta "plat-flow:kind" "policy"
  body

-- | ガード条件（operation 内で使用）
guard_ :: Text -> Text -> DeclWriter 'Operation ()
guard_ name condition = meta ("plat-flow:guard:" <> name) condition

flowRules :: [SomeRule]
flowRules = []

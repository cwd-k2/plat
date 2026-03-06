-- | Design by Contract 拡張: pre, post, assert_
module Plat.Ext.DBC
  ( pre
  , post
  , assert_
  , dbcRules
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import Plat.Core.Types
import Plat.Core.Builder
import Plat.Check.Class

-- | 事前条件（operation コンテキスト）
pre :: Text -> Text -> DeclWriter 'Operation ()
pre name expr = meta ("plat-dbc:pre:" <> name) expr

-- | 事後条件（operation コンテキスト）
post :: Text -> Text -> DeclWriter 'Operation ()
post name expr = meta ("plat-dbc:post:" <> name) expr

-- | アサーション（任意の DeclWriter コンテキスト）
assert_ :: Text -> Text -> DeclWriter k ()
assert_ name expr = meta ("plat-dbc:assert:" <> name) expr

----------------------------------------------------------------------
-- DBC Rules
----------------------------------------------------------------------

-- | DBC-W001: operation with contracts has no dependencies
data ContractNeedsRule = ContractNeedsRule
instance PlatRule ContractNeedsRule where
  ruleCode _ = "DBC-W001"
  checkDecl _ _ d
    | declKind d == Operation
    , hasContract d
    , null (declNeeds d)
    = [ Diagnostic Warning "DBC-W001"
          "operation with contracts has no dependencies"
          (declName d) Nothing
      ]
    | otherwise = []

hasContract :: Declaration -> Bool
hasContract d = any (\(k, _) -> T.isPrefixOf "plat-dbc:pre:" k
                             || T.isPrefixOf "plat-dbc:post:" k) (declMeta d)

dbcRules :: [SomeRule]
dbcRules = [SomeRule ContractNeedsRule]

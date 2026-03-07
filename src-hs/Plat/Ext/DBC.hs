-- | Design by Contract extension: pre, post, assert_
module Plat.Ext.DBC
  ( pre
  , post
  , assert_
  , dbcRules
  -- * Meta vocabulary
  , dbc
  ) where

import Data.Text (Text)

import Plat.Core.Types
import Plat.Core.Builder
import Plat.Core.Meta
import Plat.Check.Class

-- | DBC extension identifier
dbc :: ExtId
dbc = extId "dbc"

-- | Precondition (operation context)
pre :: Text -> Text -> DeclWriter 'Operation ()
pre name expr = annotate dbc "pre" name expr

-- | Postcondition (operation context)
post :: Text -> Text -> DeclWriter 'Operation ()
post name expr = annotate dbc "post" name expr

-- | Assertion (any DeclWriter context)
assert_ :: Text -> Text -> DeclWriter k ()
assert_ name expr = annotate dbc "assert" name expr

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
hasContract d = not (null (annotations dbc "pre" d))
             || not (null (annotations dbc "post" d))

-- | DBC 拡張の検証ルール一覧 (DBC-W001)
dbcRules :: [SomeRule]
dbcRules = [SomeRule ContractNeedsRule]

-- | CQRS 拡張: command, query
module Plat.Ext.CQRS
  ( command
  , query
  , cqrsRules
  -- * Helpers
  , isCommand
  , isQuery
  ) where

import Data.Text (Text)

import Plat.Core.Types
import Plat.Core.Builder
import Plat.Check.Class

-- | Command (operation with write semantics)
command :: Text -> LayerDef -> DeclWriter 'Operation () -> Decl 'Operation
command name ly body = operation name ly $ do
  meta "plat-cqrs:kind" "command"
  body

-- | Query (operation with read semantics)
query :: Text -> LayerDef -> DeclWriter 'Operation () -> Decl 'Operation
query name ly body = operation name ly $ do
  meta "plat-cqrs:kind" "query"
  body

-- Queries

isCommand :: Declaration -> Bool
isCommand d = declKind d == Operation && lookupMeta "plat-cqrs:kind" d == Just "command"

isQuery :: Declaration -> Bool
isQuery d = declKind d == Operation && lookupMeta "plat-cqrs:kind" d == Just "query"

----------------------------------------------------------------------
-- CQRS Rules
----------------------------------------------------------------------

-- | CQRS-W001: query should not have side-effecting needs
--   (future: detect event publishers, write repos, etc.)
--   For now, this is a placeholder.

cqrsRules :: [SomeRule]
cqrsRules = []

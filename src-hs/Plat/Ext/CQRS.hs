-- | CQRS extension: command, query
module Plat.Ext.CQRS
  ( command
  , query
  , cqrsRules
  -- * Helpers
  , isCommand
  , isQuery
  -- * Meta vocabulary
  , cqrs
  , cqrsCommand
  , cqrsQuery
  ) where

import Data.Text (Text)

import Plat.Core.Types
import Plat.Core.Builder
import Plat.Core.Meta
import Plat.Check.Class

-- | CQRS extension identifier
cqrs :: ExtId
cqrs = extId "cqrs"

-- | CQRS メタタグ: command / query
cqrsCommand, cqrsQuery :: MetaTag
cqrsCommand = kind cqrs "command"
cqrsQuery   = kind cqrs "query"

-- | Command (operation with write semantics)
command :: Text -> LayerDef -> DeclWriter 'Operation () -> Decl 'Operation
command name ly body = operation name ly $ do
  tagAs cqrsCommand
  body

-- | Query (operation with read semantics)
query :: Text -> LayerDef -> DeclWriter 'Operation () -> Decl 'Operation
query name ly body = operation name ly $ do
  tagAs cqrsQuery
  body

-- Queries

-- | 宣言が command かどうか判定する
isCommand :: Declaration -> Bool
isCommand d = declKind d == Operation && isTagged cqrsCommand d

-- | 宣言が query かどうか判定する
isQuery :: Declaration -> Bool
isQuery d = declKind d == Operation && isTagged cqrsQuery d

----------------------------------------------------------------------
-- CQRS Rules
----------------------------------------------------------------------

-- | CQRS 拡張の検証ルール一覧 (現在は空)
cqrsRules :: [SomeRule]
cqrsRules = []

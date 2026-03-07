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

import qualified Data.Set as Set

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

-- | CQRS-W001: query が command と同じ boundary を needs している
--
-- strict CQRS では read/write パスを分離するため、
-- query と command が同じ boundary に依存する場合に警告する。
data QuerySharedBoundaryRule = QuerySharedBoundaryRule
instance PlatRule QuerySharedBoundaryRule where
  ruleCode _ = "CQRS-W001"
  checkArch _ a =
    [ Diagnostic Warning "CQRS-W001"
        ("query " <> declName q <> " shares boundary " <> bnd <> " with commands")
        (declName q) (Just bnd)
    | q <- archDecls a, isQuery q
    , bnd <- declNeeds q
    , bnd `Set.member` commandNeeds
    ]
    where
      commandNeeds = Set.fromList
        [ n | c <- archDecls a, isCommand c, n <- declNeeds c ]

-- | CQRS-V001: command が出力型を持つべきでない (CQS 原則)。
--
-- command は副作用を実行するが値を返さない。出力型が定義されている場合に警告する。
data CommandNoOutputRule = CommandNoOutputRule
instance PlatRule CommandNoOutputRule where
  ruleCode _ = "CQRS-V001"
  checkDecl _ _ d
    | isCommand d
    , not (null [() | Output _ _ <- declBody d])
    = [ Diagnostic Warning "CQRS-V001"
          ("command " <> declName d <> " should not have output (CQS principle)")
          (declName d) Nothing
      ]
    | otherwise = []

-- | CQRS 拡張の検証ルール一覧
cqrsRules :: [SomeRule]
cqrsRules =
  [ SomeRule QuerySharedBoundaryRule
  , SomeRule CommandNoOutputRule
  ]

module Arch.Port (accountRepo, eventStore, statementStore, declareAll) where

import Plat.Core

import Arch.Layers
import Arch.Domain (accountId, account, statement)

accountRepo :: Decl 'Boundary
accountRepo = boundary "AccountRepository" dom $ do
  op "load"  ["id" .: ref accountId] ["account" .: ref account, "err" .: error_]
  op "save"  ["account" .: ref account] ["err" .: error_]

eventStore :: Decl 'Boundary
eventStore = boundary "EventStore" dom $ do
  op "append"  ["id" .: ref accountId, "events" .: list any_]  ["err" .: error_]
  op "loadAll" ["id" .: ref accountId] ["events" .: list any_, "err" .: error_]

statementStore :: Decl 'Boundary
statementStore = boundary "StatementStore" dom $ do
  op "save"          ["statement" .: ref statement]   ["err" .: error_]
  op "findByAccount" ["accountId" .: ref accountId]   ["statements" .: list (ref statement), "err" .: error_]

declareAll :: ArchBuilder ()
declareAll = do
  declare accountRepo
  declare eventStore
  declare statementStore

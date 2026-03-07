module Arch.Infra (pgEventStore, pgAccountRepo, pgStatementStore, declareAll) where

import Plat.Core

import Arch.Layers
import Arch.Port (accountRepo, eventStore, statementStore)

pgEventStore :: Decl 'Adapter
pgEventStore = adapter "PostgresEventStore" infra $ do
  implements eventStore
  inject "pool" (ext "sqlx::PgPool")

pgAccountRepo :: Decl 'Adapter
pgAccountRepo = adapter "PostgresAccountRepo" infra $ do
  implements accountRepo
  inject "pool" (ext "sqlx::PgPool")

pgStatementStore :: Decl 'Adapter
pgStatementStore = adapter "PostgresStatementStore" infra $ do
  implements statementStore
  inject "pool" (ext "sqlx::PgPool")

declareAll :: ArchBuilder ()
declareAll = do
  declare pgEventStore
  declare pgAccountRepo
  declare pgStatementStore

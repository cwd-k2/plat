module Arch.Shared (money, address, declareAll) where

import Plat.Core
import Plat.Ext.CleanArch
import Plat.Ext.DDD

money :: Decl 'Model
money = value "Money" enterprise $ do
  field "amount"   decimal
  field "currency" string

address :: Decl 'Model
address = value "Address" enterprise $ do
  field "street"  string
  field "city"    string
  field "country" string

declareAll :: ArchBuilder ()
declareAll = do
  declare money
  declare address

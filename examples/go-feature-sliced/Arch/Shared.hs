module Arch.Shared (money, address, sharedModule, declareAll) where

import Plat.Core
import Plat.Ext.CleanArch
import Plat.Ext.DDD
import Plat.Ext.Modules

----------------------------------------------------------------------
-- Shared kernel (enterprise layer)
----------------------------------------------------------------------

money :: Decl 'Model
money = value "Money" enterprise $ do
  field "amount"   decimal
  field "currency" string

address :: Decl 'Model
address = value "Address" enterprise $ do
  field "street"  string
  field "city"    string
  field "country" string
  field "zip"     string

sharedModule :: Decl 'Compose
sharedModule = domain "SharedKernel" $ do
  expose money
  expose address

declareAll :: ArchBuilder ()
declareAll = do
  declare money
  declare address
  declare sharedModule

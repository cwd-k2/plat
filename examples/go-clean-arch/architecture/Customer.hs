module Customer (customer, customerStatus, customerRepo, createCustomer, getCustomer, updateCustomerAddress, pgCustomerRepo, declareAll) where

import Plat.Core
import Plat.Ext.CleanArch
import Plat.Ext.DDD

import Shared (address)

customer :: Decl 'Model
customer = aggregate "Customer" enterprise $ do
  field "id"        (customType "UUID")
  field "name"      string
  field "email"     string
  field "phone"     string
  field "address"   (ref address)
  field "createdAt" dateTime

customerStatus :: Decl 'Model
customerStatus = enum "CustomerStatus" enterprise
  ["Active", "Suspended", "Deleted"]

customerRepo :: Decl 'Boundary
customerRepo = port "CustomerRepository" interface $ do
  op "save"        ["customer" .: ref customer] ["err" .: error_]
  op "findById"    ["id" .: customType "UUID"] ["customer" .: ref customer, "err" .: error_]
  op "findByEmail" ["email" .: string] ["customer" .: ref customer, "err" .: error_]
  op "delete"      ["id" .: customType "UUID"] ["err" .: error_]

createCustomer :: Decl 'Operation
createCustomer = usecase "CreateCustomer" application $ do
  input  "customer" (ref customer)
  output "err"      error_
  needs customerRepo

getCustomer :: Decl 'Operation
getCustomer = usecase "GetCustomer" application $ do
  input  "customerId" (customType "UUID")
  output "customer"   (ref customer)
  output "err"        error_
  needs customerRepo

updateCustomerAddress :: Decl 'Operation
updateCustomerAddress = usecase "UpdateCustomerAddress" application $ do
  input  "customerId" (customType "UUID")
  input  "address"    (ref address)
  output "err"        error_
  needs customerRepo

pgCustomerRepo :: Decl 'Adapter
pgCustomerRepo = impl "PostgresCustomerRepo" framework customerRepo $ do
  inject "db" (ext "*sql.DB")

declareAll :: ArchBuilder ()
declareAll = do
  declare customer
  declare customerStatus
  declare customerRepo
  declare createCustomer
  declare getCustomer
  declare updateCustomerAddress
  declare pgCustomerRepo

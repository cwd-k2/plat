module Payment (
  paymentStatus, payment,
  paymentGateway, paymentRepo,
  processPayment, getPayment,
  memPaymentRepo, stubPaymentGateway,
  paymentModule,
  declareAll
) where

import Plat.Core
import Plat.Ext.CleanArch
import Plat.Ext.DDD
import Plat.Ext.Modules
import Shared (money)

----------------------------------------------------------------------
-- Feature: Payment
----------------------------------------------------------------------

-- Domain

paymentStatus :: Decl 'Model
paymentStatus = enum_ "PaymentStatus" enterprise
  ["Pending", "Completed", "Failed", "Refunded"]

payment :: Decl 'Model
payment = model "Payment" enterprise $ do
  field "id"            (customType "UUID")
  field "orderId"       (customType "UUID")
  field "amount"        (ref money)
  field "status"        (ref paymentStatus)
  field "transactionId" string

-- Ports

paymentGateway :: Decl 'Boundary
paymentGateway = port "PaymentGateway" interface $ do
  op "charge" ["amount" .: ref money, "token" .: string] ["txId" .: string, "err" .: error_]
  op "refund" ["txId" .: string] ["err" .: error_]

paymentRepo :: Decl 'Boundary
paymentRepo = port "PaymentRepository" interface $ do
  op "save"         ["payment" .: ref payment] ["err" .: error_]
  op "findByOrder"  ["orderId" .: customType "UUID"] ["payment" .: ref payment, "err" .: error_]

-- Use cases

processPayment :: Decl 'Operation
processPayment = usecase "ProcessPayment" application $ do
  input  "orderId"      (customType "UUID")
  input  "amount"       (ref money)
  input  "paymentToken" string
  output "paymentId"    (customType "UUID")
  output "err"          error_
  needs paymentGateway
  needs paymentRepo

getPayment :: Decl 'Operation
getPayment = usecase "GetPayment" application $ do
  input  "orderId"  (customType "UUID")
  output "payment"  (ref payment)
  output "err"      error_
  needs paymentRepo

-- Adapters

memPaymentRepo :: Decl 'Adapter
memPaymentRepo = impl_ "InMemoryPaymentRepo" framework paymentRepo $ do
  inject "store" (ext "sync.Map")

stubPaymentGateway :: Decl 'Adapter
stubPaymentGateway = impl_ "StubPaymentGateway" framework paymentGateway $ do
  inject "logger" (ext "log.Logger")

-- Module

paymentModule :: Decl 'Compose
paymentModule = domain "PaymentFeature" $ do
  expose payment
  expose paymentStatus
  expose paymentGateway
  expose paymentRepo
  expose processPayment
  expose getPayment
  expose memPaymentRepo
  expose stubPaymentGateway

declareAll :: ArchBuilder ()
declareAll = do
  declare paymentStatus
  declare payment
  declare paymentGateway
  declare paymentRepo
  declare processPayment
  declare getPayment
  declare memPaymentRepo
  declare stubPaymentGateway
  declare paymentModule

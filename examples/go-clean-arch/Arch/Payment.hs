module Arch.Payment (paymentRecord, paymentGateway, stripePayment, declareAll) where

import Plat.Core
import Plat.Ext.CleanArch

import Arch.Shared (money)

paymentRecord :: Decl 'Model
paymentRecord = model "PaymentRecord" enterprise $ do
  field "id"            (customType "UUID")
  field "orderId"       (customType "UUID")
  field "amount"        (ref money)
  field "method"        string
  field "status"        string
  field "transactionId" string

paymentGateway :: Decl 'Boundary
paymentGateway = port "PaymentGateway" interface $ do
  op "charge" ["amount" .: ref money, "token" .: string] ["txId" .: string, "err" .: error_]
  op "refund" ["txId" .: string] ["err" .: error_]

stripePayment :: Decl 'Adapter
stripePayment = impl_ "StripePayment" framework paymentGateway $ do
  inject "client" (ext "*stripe.Client")

declareAll :: ArchBuilder ()
declareAll = do
  declare paymentRecord
  declare paymentGateway
  declare stripePayment

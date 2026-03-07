module Catalog (product_, category, productRepo, inventoryChecker, createProduct, getProduct, searchProducts, pgProductRepo, stubInventory, declareAll) where

import Plat.Core
import Plat.Ext.CleanArch

import Shared (money)

product_ :: Decl 'Model
product_ = model "Product" enterprise $ do
  field "id"          (customType "UUID")
  field "name"        string
  field "description" string
  field "price"       (ref money)
  field "categoryId"  string
  field "stock"       int

category :: Decl 'Model
category = model "Category" enterprise $ do
  field "id"          string
  field "name"        string
  field "description" string

productRepo :: Decl 'Boundary
productRepo = port "ProductRepository" interface $ do
  op "save"     ["product" .: ref product_] ["err" .: error_]
  op "findById" ["id" .: customType "UUID"] ["product" .: ref product_, "err" .: error_]
  op "findAll"  [] ["products" .: list (ref product_), "err" .: error_]
  op "search"   ["query" .: string] ["products" .: list (ref product_), "err" .: error_]
  op "delete"   ["id" .: customType "UUID"] ["err" .: error_]

inventoryChecker :: Decl 'Boundary
inventoryChecker = port "InventoryChecker" interface $ do
  op "check" ["productId" .: customType "UUID", "quantity" .: int] ["available" .: bool, "err" .: error_]

createProduct :: Decl 'Operation
createProduct = usecase "CreateProduct" application $ do
  input  "product" (ref product_)
  output "err"     error_
  needs productRepo

getProduct :: Decl 'Operation
getProduct = usecase "GetProduct" application $ do
  input  "productId" (customType "UUID")
  output "product"   (ref product_)
  output "err"       error_
  needs productRepo

searchProducts :: Decl 'Operation
searchProducts = usecase "SearchProducts" application $ do
  input  "query"    string
  output "products" (list (ref product_))
  output "err"      error_
  needs productRepo

pgProductRepo :: Decl 'Adapter
pgProductRepo = impl_ "PostgresProductRepo" framework productRepo $ do
  inject "db" (ext "*sql.DB")

stubInventory :: Decl 'Adapter
stubInventory = impl_ "StubInventory" framework inventoryChecker $ do
  inject "db" (ext "*sql.DB")

declareAll :: ArchBuilder ()
declareAll = do
  declare product_
  declare category
  declare productRepo
  declare inventoryChecker
  declare createProduct
  declare getProduct
  declare searchProducts
  declare pgProductRepo
  declare stubInventory

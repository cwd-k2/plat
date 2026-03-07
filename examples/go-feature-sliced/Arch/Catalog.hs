module Arch.Catalog (
  category, product_,
  productRepo, productSearch,
  createProduct, getProduct, searchProducts,
  memProductRepo, memProductSearch,
  catalogModule,
  declareAll
) where

import Plat.Core
import Plat.Ext.CleanArch
import Plat.Ext.Modules
import Arch.Shared (money)

----------------------------------------------------------------------
-- Feature: Catalog
----------------------------------------------------------------------

-- Domain

category :: Decl 'Model
category = model "Category" enterprise $ do
  field "id"          string
  field "name"        string
  field "description" string

product_ :: Decl 'Model
product_ = model "Product" enterprise $ do
  field "id"          (customType "UUID")
  field "name"        string
  field "description" string
  field "price"       (ref money)
  field "categoryId"  string
  field "stock"       int

-- Ports

productRepo :: Decl 'Boundary
productRepo = port "ProductRepository" interface $ do
  op "save"     ["product" .: ref product_] ["err" .: error_]
  op "findById" ["id" .: customType "UUID"] ["product" .: ref product_, "err" .: error_]
  op "findAll"  [] ["products" .: list (ref product_), "err" .: error_]
  op "delete"   ["id" .: customType "UUID"] ["err" .: error_]

productSearch :: Decl 'Boundary
productSearch = port "ProductSearch" interface $ do
  op "search" ["query" .: string] ["products" .: list (ref product_), "err" .: error_]

-- Use cases

createProduct :: Decl 'Operation
createProduct = usecase "CreateProduct" application $ do
  input  "product" (ref product_)
  output "id"      (customType "UUID")
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
  needs productSearch

-- Adapters

memProductRepo :: Decl 'Adapter
memProductRepo = impl_ "InMemoryProductRepo" framework productRepo $ do
  inject "store" (ext "sync.Map")

memProductSearch :: Decl 'Adapter
memProductSearch = impl_ "InMemoryProductSearch" framework productSearch $ do
  inject "store" (ext "sync.Map")

-- Module

catalogModule :: Decl 'Compose
catalogModule = domain "CatalogFeature" $ do
  expose category
  expose product_
  expose productRepo
  expose productSearch
  expose createProduct
  expose getProduct
  expose searchProducts
  expose memProductRepo
  expose memProductSearch

declareAll :: ArchBuilder ()
declareAll = do
  declare category
  declare product_
  declare productRepo
  declare productSearch
  declare createProduct
  declare getProduct
  declare searchProducts
  declare memProductRepo
  declare memProductSearch
  declare catalogModule

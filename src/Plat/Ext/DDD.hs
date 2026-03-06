-- | DDD 拡張: value, aggregate, enum_, invariant
module Plat.Ext.DDD
  ( value
  , aggregate
  , enum_
  , invariant
  , dddRules
  -- * Helpers
  , isValue
  , isAggregate
  , isEnum
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Control.Monad (forM_)

import Plat.Core.Types
import Plat.Core.Builder
import Plat.Check.Class

-- | Value Object
value :: Text -> LayerDef -> DeclWriter 'Model () -> Decl 'Model
value name ly body = model name ly $ do
  meta "plat-ddd:kind" "value"
  body

-- | Aggregate Root
aggregate :: Text -> LayerDef -> DeclWriter 'Model () -> Decl 'Model
aggregate name ly body = model name ly $ do
  meta "plat-ddd:kind" "aggregate"
  body

-- | Enum (variants as metadata)
enum_ :: Text -> LayerDef -> [Text] -> Decl 'Model
enum_ name ly variants = model name ly $ do
  meta "plat-ddd:kind" "enum"
  forM_ variants $ \v -> meta ("plat-ddd:variant:" <> v) v

-- | Invariant (model context only)
invariant :: Text -> Text -> DeclWriter 'Model ()
invariant name expr = meta ("plat-ddd:invariant:" <> name) expr

-- Queries

isValue :: Declaration -> Bool
isValue d = declKind d == Model && lookupMeta "plat-ddd:kind" d == Just "value"

isAggregate :: Declaration -> Bool
isAggregate d = declKind d == Model && lookupMeta "plat-ddd:kind" d == Just "aggregate"

isEnum :: Declaration -> Bool
isEnum d = declKind d == Model && lookupMeta "plat-ddd:kind" d == Just "enum"

----------------------------------------------------------------------
-- DDD Rules
----------------------------------------------------------------------

-- | DDD-V001: value object must not have an Id field
data ValueNoIdRule = ValueNoIdRule
instance PlatRule ValueNoIdRule where
  ruleCode _ = "DDD-V001"
  checkDecl _ _ d
    | isValue d, any isIdField (declBody d)
    = [ Diagnostic Error "DDD-V001"
          "value object must not have an Id field"
          (declName d) Nothing
      ]
    | otherwise = []

isIdField :: DeclItem -> Bool
isIdField (Field name _) = T.toLower name == "id"
isIdField _              = False

-- | DDD-V002: aggregate must have an Id field
data AggregateIdRule = AggregateIdRule
instance PlatRule AggregateIdRule where
  ruleCode _ = "DDD-V002"
  checkDecl _ _ d
    | isAggregate d, not (any isIdField (declBody d))
    = [ Diagnostic Warning "DDD-V002"
          "aggregate should have an Id field"
          (declName d) Nothing
      ]
    | otherwise = []

dddRules :: [SomeRule]
dddRules =
  [ SomeRule ValueNoIdRule
  , SomeRule AggregateIdRule
  ]

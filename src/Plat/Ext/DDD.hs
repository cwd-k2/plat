-- | DDD extension: value, aggregate, enum_, invariant
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
  -- * Meta vocabulary
  , ddd
  , dddValue
  , dddAggregate
  , dddEnum
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Control.Monad (forM_)

import Plat.Core.Types
import Plat.Core.Builder
import Plat.Core.Meta
import Plat.Check.Class

-- | DDD extension identifier
ddd :: ExtId
ddd = extId "ddd"

dddValue, dddAggregate, dddEnum :: MetaTag
dddValue     = kind ddd "value"
dddAggregate = kind ddd "aggregate"
dddEnum      = kind ddd "enum"

-- | Value Object
value :: Text -> LayerDef -> DeclWriter 'Model () -> Decl 'Model
value name ly body = model name ly $ do
  tagAs dddValue
  body

-- | Aggregate Root
aggregate :: Text -> LayerDef -> DeclWriter 'Model () -> Decl 'Model
aggregate name ly body = model name ly $ do
  tagAs dddAggregate
  body

-- | Enum (variants as metadata)
enum_ :: Text -> LayerDef -> [Text] -> Decl 'Model
enum_ name ly variants = model name ly $ do
  tagAs dddEnum
  forM_ variants $ \v -> annotate ddd "variant" v v

-- | Invariant (model context only)
invariant :: Text -> Text -> DeclWriter 'Model ()
invariant name expr = annotate ddd "invariant" name expr

-- Queries

isValue :: Declaration -> Bool
isValue d = declKind d == Model && isTagged dddValue d

isAggregate :: Declaration -> Bool
isAggregate d = declKind d == Model && isTagged dddAggregate d

isEnum :: Declaration -> Bool
isEnum d = declKind d == Model && isTagged dddEnum d

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

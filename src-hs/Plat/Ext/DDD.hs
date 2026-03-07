-- | DDD extension: value, aggregate, enum, invariant
module Plat.Ext.DDD
  ( value
  , aggregate
  , enum
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

-- | DDD メタタグ: value object / aggregate root / enum
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
enum :: Text -> LayerDef -> [Text] -> Decl 'Model
enum name ly variants = model name ly $ do
  tagAs dddEnum
  forM_ variants $ \v -> annotate ddd "variant" v v

-- | Invariant (model context only)
invariant :: Text -> Text -> DeclWriter 'Model ()
invariant name expr = annotate ddd "invariant" name expr

-- Queries

-- | 宣言が value object かどうか判定する
isValue :: Declaration -> Bool
isValue d = declKind d == Model && isTagged dddValue d

-- | 宣言が aggregate root かどうか判定する
isAggregate :: Declaration -> Bool
isAggregate d = declKind d == Model && isTagged dddAggregate d

-- | 宣言が enum かどうか判定する
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

-- | DDD 拡張の検証ルール一覧 (DDD-V001, DDD-V002)
dddRules :: [SomeRule]
dddRules =
  [ SomeRule ValueNoIdRule
  , SomeRule AggregateIdRule
  ]

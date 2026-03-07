-- | Structured meta DSL for extensions.
--
-- Provides typed helpers over the raw @meta@ key-value pairs,
-- ensuring consistent namespacing and eliminating magic strings.
--
-- Four patterns cover all extension meta usage:
--
-- 1. Kind tag — classifies a declaration (@tagAs@, @isTagged@)
-- 2. Attribute — simple key-value pair (@attr@, @lookupAttr@)
-- 3. Annotation — named sub-keyed entry (@annotate@, @annotations@)
-- 4. Reference — link to another declaration (@refer@, @references@)
module Plat.Core.Meta
  ( -- * Extension identity
    ExtId
  , extId

    -- * Kind tags
  , MetaTag
  , kind
  , tagAs
  , isTagged

    -- * Attributes (simple key-value)
  , attr
  , lookupAttr

    -- * Named annotations (sub-keyed)
  , annotate
  , annotations

    -- * References to other declarations
  , refer
  , references
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import Plat.Core.Types
import Plat.Core.Builder (DeclWriter, meta)

----------------------------------------------------------------------
-- Extension identity
----------------------------------------------------------------------

-- | Extension identifier. Namespaces all meta keys under @plat-{id}:@.
newtype ExtId = ExtId Text
  deriving stock (Show, Eq)

-- | Create an extension identifier.
extId :: Text -> ExtId
extId = ExtId

----------------------------------------------------------------------
-- Kind tags
----------------------------------------------------------------------

-- | A kind tag classifies a declaration within an extension's domain.
data MetaTag = MetaTag ExtId Text
  deriving stock (Show, Eq)

-- | Define a kind tag.
kind :: ExtId -> Text -> MetaTag
kind = MetaTag

-- | Tag the current declaration with a kind.
tagAs :: MetaTag -> DeclWriter k ()
tagAs (MetaTag (ExtId ext) val) = meta ("plat-" <> ext <> ":kind") val

-- | Check if a declaration carries a specific kind tag.
isTagged :: MetaTag -> Declaration -> Bool
isTagged (MetaTag (ExtId ext) val) d =
  lookupMeta ("plat-" <> ext <> ":kind") d == Just val

----------------------------------------------------------------------
-- Attributes
----------------------------------------------------------------------

-- | Set a simple attribute on the current declaration.
attr :: ExtId -> Text -> Text -> DeclWriter k ()
attr (ExtId ext) key val = meta ("plat-" <> ext <> ":" <> key) val

-- | Look up a simple attribute.
lookupAttr :: ExtId -> Text -> Declaration -> Maybe Text
lookupAttr (ExtId ext) key = lookupMeta ("plat-" <> ext <> ":" <> key)

----------------------------------------------------------------------
-- Named annotations
----------------------------------------------------------------------

-- | Add a named annotation under a category.
annotate :: ExtId -> Text -> Text -> Text -> DeclWriter k ()
annotate (ExtId ext) cat name val =
  meta ("plat-" <> ext <> ":" <> cat <> ":" <> name) val

-- | Query all annotations in a category. Returns @[(name, value)]@.
annotations :: ExtId -> Text -> Declaration -> [(Text, Text)]
annotations (ExtId ext) cat d =
  [ (T.drop (T.length pfx) k, v)
  | (k, v) <- declMeta d
  , pfx `T.isPrefixOf` k
  ]
  where pfx = "plat-" <> ext <> ":" <> cat <> ":"

----------------------------------------------------------------------
-- References
----------------------------------------------------------------------

-- | Record a reference to another declaration.
refer :: ExtId -> Text -> Decl j -> DeclWriter k ()
refer ext cat (Decl d) = annotate ext cat (declName d) (declName d)

-- | Query all references in a category. Returns declaration names.
references :: ExtId -> Text -> Declaration -> [Text]
references ext cat d = map snd (annotations ext cat d)

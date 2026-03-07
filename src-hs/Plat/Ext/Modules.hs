-- | Modules extension: domain, expose, import_
module Plat.Ext.Modules
  ( domain
  , expose
  , import_
  , modulesRules
  -- * Meta vocabulary
  , modules
  , modulesDomain
  ) where

import Data.Text (Text)

import Plat.Core.Types
import Plat.Core.Builder
import Plat.Core.Meta
import Plat.Check.Class

-- | Modules extension identifier
modules :: ExtId
modules = extId "modules"

-- | ドメインモジュールのメタタグ
modulesDomain :: MetaTag
modulesDomain = kind modules "domain"

-- | Domain module (compose: grouping of declarations)
domain :: Text -> DeclWriter 'Compose () -> Decl 'Compose
domain name body = compose name $ do
  tagAs modulesDomain
  body

-- | Expose a declaration from a module
expose :: Decl k -> DeclWriter 'Compose ()
expose d = do
  refer modules "expose" d
  entry d

-- | Import a declaration from another module (recorded as metadata)
import_ :: Decl 'Compose -> Decl k -> DeclWriter 'Compose ()
import_ src target =
  annotate modules "import" (declName (unDecl target)) (declName (unDecl src))

-- | Modules 拡張の検証ルール一覧 (現在は空)
modulesRules :: [SomeRule]
modulesRules = []

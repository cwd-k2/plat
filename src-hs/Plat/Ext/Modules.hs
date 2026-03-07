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

import qualified Data.Set as Set

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

----------------------------------------------------------------------
-- Modules Rules
----------------------------------------------------------------------

-- | MOD-V001: expose された宣言が Architecture 内に存在すること
data ExposeExistsRule = ExposeExistsRule
instance PlatRule ExposeExistsRule where
  ruleCode _ = "MOD-V001"
  checkDecl _ a d
    | isTagged modulesDomain d
    = [ Diagnostic Error "MOD-V001"
          ("module " <> declName d <> " exposes unknown declaration " <> expName)
          (declName d) (Just expName)
      | expName <- references modules "expose" d
      , expName `Set.notMember` declNames
      ]
    | otherwise = []
    where declNames = Set.fromList [declName dd | dd <- archDecls a]

-- | MOD-V002: import のソースモジュールが存在すること
data ImportSourceExistsRule = ImportSourceExistsRule
instance PlatRule ImportSourceExistsRule where
  ruleCode _ = "MOD-V002"
  checkDecl _ a d
    | isTagged modulesDomain d
    = [ Diagnostic Error "MOD-V002"
          ("module " <> declName d <> " imports from unknown module " <> srcName)
          (declName d) (Just srcName)
      | (_, srcName) <- annotations modules "import" d
      , srcName `Set.notMember` declNames
      ]
    | otherwise = []
    where declNames = Set.fromList [declName dd | dd <- archDecls a]

-- | MOD-W001: import された宣言がソースモジュールで expose されていない
data ImportNotExposedRule = ImportNotExposedRule
instance PlatRule ImportNotExposedRule where
  ruleCode _ = "MOD-W001"
  checkDecl _ a d
    | isTagged modulesDomain d
    = [ Diagnostic Warning "MOD-W001"
          ("module " <> declName d <> " imports " <> targetName
           <> " from " <> srcName <> " but it is not exposed")
          (declName d) (Just targetName)
      | (targetName, srcName) <- annotations modules "import" d
      , srcName `Set.member` declNames
      , not (isExposedBy srcName targetName)
      ]
    | otherwise = []
    where
      declNames = Set.fromList [declName dd | dd <- archDecls a]
      isExposedBy modName target =
        any (\dd -> declName dd == modName
                 && target `elem` references modules "expose" dd)
            (archDecls a)

-- | Modules 拡張の検証ルール一覧
modulesRules :: [SomeRule]
modulesRules =
  [ SomeRule ExposeExistsRule
  , SomeRule ImportSourceExistsRule
  , SomeRule ImportNotExposedRule
  ]

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

-- | MOD-V003: モジュール外からの expose されていない宣言への references 参照を検出。
--
-- domain モジュールが宣言のスコープを制限する。expose されていない宣言を
-- 他モジュールの宣言から型参照している場合にエラーとする。
data UnexposedReferenceRule = UnexposedReferenceRule
instance PlatRule UnexposedReferenceRule where
  ruleCode _ = "MOD-V003"
  checkArch _ a =
    [ Diagnostic Error "MOD-V003"
        (refSrc <> " references unexposed " <> refTgt <> " from module " <> tgtMod)
        refSrc (Just refTgt)
    | (refSrc, refTgt) <- allRefs
    , let srcMod = ownerModule refSrc
    , let tgtMod_ = ownerModule refTgt
    , Just tgtMod <- [tgtMod_]
    , srcMod /= tgtMod_
    , refTgt `Set.notMember` exposedByModule tgtMod
    ]
    where
      mods = [d | d <- archDecls a, isTagged modulesDomain d]

      moduleEntries = Set.fromList
        [ (declName m, e)
        | m <- mods
        , Entry e <- declBody m
        ]

      allEntryNames = Set.fromList [e | (_, e) <- Set.toList moduleEntries]

      ownerModule name =
        case [declName m | m <- mods, Entry name `elem` declBody m] of
          (m:_) -> Just m
          []    -> Nothing

      exposedByModule modName =
        Set.fromList [ ref
                     | m <- mods
                     , declName m == modName
                     , ref <- references modules "expose" m
                     ]

      allRefs =
        [ (declName d, tgt)
        | d <- archDecls a
        , not (isTagged modulesDomain d)
        , item <- declBody d
        , tgt <- itemRefTargets item
        , tgt `Set.member` allEntryNames
        ]

      itemRefTargets (Field _ ty)  = typeRefNames ty
      itemRefTargets (Input _ ty)  = typeRefNames ty
      itemRefTargets (Output _ ty) = typeRefNames ty
      itemRefTargets (Needs n)     = [n]
      itemRefTargets _             = []

      typeRefNames (TRef n)        = [n]
      typeRefNames (TGeneric _ ts) = concatMap typeRefNames ts
      typeRefNames (TNullable t)   = typeRefNames t
      typeRefNames _               = []

-- | Modules 拡張の検証ルール一覧
modulesRules :: [SomeRule]
modulesRules =
  [ SomeRule ExposeExistsRule
  , SomeRule ImportSourceExistsRule
  , SomeRule ImportNotExposedRule
  , SomeRule UnexposedReferenceRule
  ]

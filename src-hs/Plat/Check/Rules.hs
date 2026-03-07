-- | コア検証ルール群 (V001-V009, W001-W003)。
--
-- 'coreRules' が全ルールを含む標準セット。
-- 個別ルールを選択的に組み合わせることも可能。
module Plat.Check.Rules
  ( coreRules
  -- * Individual rules (for selective composition)
  , LayerDepRule (..)
  , LayerCycleRule (..)
  , NeedsKindRule (..)
  , BoundaryKindRule (..)
  , BindScopeRule (..)
  , KeywordCollisionRule (..)
  , AdapterCoverageRule (..)
  , BindTargetRule (..)
  , UnresolvedBoundaryRule (..)
  , UndefinedTypeRule (..)
  , UniqueNameRule (..)
  , MultipleImplementsRule (..)
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import qualified Data.Set as Set

import Plat.Core.Types
import Plat.Check.Class

----------------------------------------------------------------------
-- coreRules
----------------------------------------------------------------------

-- | 標準検証ルールセット。V001-V008 の違反ルールと W001-W002 の警告ルールを含む。
coreRules :: [SomeRule]
coreRules =
  [ SomeRule LayerDepRule
  , SomeRule LayerCycleRule
  , SomeRule NeedsKindRule
  , SomeRule BoundaryKindRule
  , SomeRule BindScopeRule
  , SomeRule KeywordCollisionRule
  , SomeRule AdapterCoverageRule
  , SomeRule BindTargetRule
  , SomeRule UnresolvedBoundaryRule
  , SomeRule UndefinedTypeRule
  , SomeRule UniqueNameRule
  , SomeRule MultipleImplementsRule
  ]

----------------------------------------------------------------------
-- V001: レイヤー依存違反
----------------------------------------------------------------------

-- | V001: レイヤー依存違反の検出。許可されていないレイヤーへの参照を検出する。
data LayerDepRule = LayerDepRule
instance PlatRule LayerDepRule where
  ruleCode _ = "V001"
  checkDecl _ arch d
    | Just srcLayer <- declLayer d
    = concatMap (checkRef srcLayer) (referencedLayers d arch)
    | otherwise = []
    where
      layerDepMap = Map.fromList
        [(layerName l, Set.fromList (layerDeps l)) | l <- archLayers arch]

      allowedDeps src = Map.findWithDefault Set.empty src layerDepMap

      checkRef src tgtLayer
        | src == tgtLayer = []  -- same layer is OK
        | tgtLayer `Set.member` allowedDeps src = []
        | otherwise =
            [ Diagnostic Error "V001"
                ("layer " <> src <> " cannot depend on " <> tgtLayer)
                (declName d) (Just tgtLayer)
            ]

-- | 宣言が参照するレイヤーを収集
referencedLayers :: Declaration -> Architecture -> [Text]
referencedLayers d arch = mapMaybe lookupLayer refNames
  where
    declMap = Map.fromList [(declName dd, dd) | dd <- archDecls arch]
    lookupLayer name = declLayer =<< Map.lookup name declMap

    refNames = case declKind d of
      Operation -> declNeeds d
      Adapter   -> maybe [] pure (findImplements (declBody d))
                   ++ [name | Inject _ (TRef name) <- declBody d, Map.member name declMap]
      Compose   -> [bnd | Bind bnd _ <- declBody d]
                   ++ [adp | Bind _ adp <- declBody d]
      _         -> []

----------------------------------------------------------------------
-- V002: レイヤー循環依存
----------------------------------------------------------------------

-- | V002: レイヤー依存グラフの循環検出。
data LayerCycleRule = LayerCycleRule
instance PlatRule LayerCycleRule where
  ruleCode _ = "V002"
  checkArch _ arch
    | hasCycle (archLayers arch) =
        [ Diagnostic Error "V002"
            "layer dependency graph contains a cycle"
            (archName arch) Nothing
        ]
    | otherwise = []

-- | 簡易トポロジカルソートによる循環検出
hasCycle :: [LayerDef] -> Bool
hasCycle layers = go Set.empty Set.empty (map layerName layers)
  where
    depMap = Map.fromList [(layerName l, layerDeps l) | l <- layers]
    go _ _ [] = False
    go visited inStack (n:ns)
      | n `Set.member` visited = go visited inStack ns
      | otherwise = dfs visited inStack n || go visited inStack ns
    dfs visited inStack n
      | n `Set.member` inStack = True
      | n `Set.member` visited = False
      | otherwise =
          let inStack' = Set.insert n inStack
              deps = Map.findWithDefault [] n depMap
          in  any (dfs visited inStack') deps
              -- n is now fully visited after exploring deps
              -- (simplified: if any dep cycles, we report True)

----------------------------------------------------------------------
-- V003: needs に adapter 指定
----------------------------------------------------------------------

-- | V003: @needs@ の対象が boundary でない場合の検出。
data NeedsKindRule = NeedsKindRule
instance PlatRule NeedsKindRule where
  ruleCode _ = "V003"
  checkDecl _ arch d =
    [ Diagnostic Error "V003"
        ("needs target " <> name <> " is not a boundary")
        (declName d) (Just name)
    | Needs name <- declBody d
    , Just target <- [Map.lookup name declMap]
    , declKind target /= Boundary
    ]
    where declMap = Map.fromList [(declName dd, dd) | dd <- archDecls arch]

----------------------------------------------------------------------
-- V004: boundary に adapter 型
----------------------------------------------------------------------

-- | V004: boundary に adapter 専用アイテム (@Inject@, @Implements@) が含まれる場合の検出。
data BoundaryKindRule = BoundaryKindRule
instance PlatRule BoundaryKindRule where
  ruleCode _ = "V004"
  checkDecl _ _ d
    | declKind d == Boundary
    , any isAdapterItem (declBody d) =
        [ Diagnostic Error "V004"
            "boundary must not contain adapter-specific items"
            (declName d) Nothing
        ]
    | otherwise = []
    where
      isAdapterItem (Inject _ _)    = True
      isAdapterItem (Implements _)  = True
      isAdapterItem _               = False

----------------------------------------------------------------------
-- V005: compose 外での bind
----------------------------------------------------------------------

-- | V005: compose 以外の宣言で @bind@ が使用された場合の検出。
data BindScopeRule = BindScopeRule
instance PlatRule BindScopeRule where
  ruleCode _ = "V005"
  checkDecl _ _ d
    | declKind d /= Compose
    , any isBind (declBody d) =
        [ Diagnostic Error "V005"
            "bind is only allowed inside compose"
            (declName d) Nothing
        ]
    | otherwise = []
    where
      isBind (Bind _ _) = True
      isBind _          = False

----------------------------------------------------------------------
-- V006: パッケージキーワード衝突
----------------------------------------------------------------------

-- | V006: 宣言名が予約キーワードと衝突する場合の検出。
data KeywordCollisionRule = KeywordCollisionRule
instance PlatRule KeywordCollisionRule where
  ruleCode _ = "V006"
  checkArch _ arch =
    [ Diagnostic Error "V006"
        ("declaration name " <> declName d <> " conflicts with reserved keyword")
        (declName d) Nothing
    | d <- archDecls arch
    , T.toLower (declName d) `Set.member` reserved
    ]
    where
      reserved = Set.fromList
        [ "model", "boundary", "operation", "adapter", "compose"
        , "layer", "type", "needs", "implements", "inject", "bind", "entry"
        ]

----------------------------------------------------------------------
-- V007: adapter が boundary の op を未宣言
----------------------------------------------------------------------

-- | V007: adapter が boundary の operation を網羅していない場合の検出。
-- adapter に Op が無い場合は暗黙的に全カバーとみなす。
data AdapterCoverageRule = AdapterCoverageRule
instance PlatRule AdapterCoverageRule where
  ruleCode _ = "V007"
  checkDecl _ arch d = case declKind d of
    Adapter
      | Just bndName <- findImplements (declBody d)
      , Just bndDecl <- Map.lookup bndName declMap
      -> let adpOps     = [name | Op name _ _ <- declBody d]
             bndOpNames = Set.fromList [name | Op name _ _ <- declBody bndDecl]
         in  if null adpOps
             then []  -- adapter に Op がなければ暗黙的に全カバー
             else
               let missing = bndOpNames `Set.difference` Set.fromList adpOps
               in  [ Diagnostic Error "V007"
                       ("adapter " <> declName d <> " does not declare op " <> opName
                        <> " from boundary " <> bndName)
                       (declName d) (Just opName)
                   | opName <- Set.toList missing
                   ]
    _ -> []
    where declMap = Map.fromList [(declName dd, dd) | dd <- archDecls arch]

----------------------------------------------------------------------
-- V008: bind の左辺が boundary、右辺が adapter であるか
----------------------------------------------------------------------

-- | V008: @bind@ の左辺が boundary、右辺が adapter であることを検証する。
data BindTargetRule = BindTargetRule
instance PlatRule BindTargetRule where
  ruleCode _ = "V008"
  checkDecl _ arch d =
    concatMap checkBind [(bnd, adp) | Bind bnd adp <- declBody d]
    where
      declMap = Map.fromList [(declName dd, dd) | dd <- archDecls arch]
      checkBind (bnd, adp) =
        [ Diagnostic Error "V008"
            ("bind left-hand side " <> bnd <> " is not a boundary")
            (declName d) (Just bnd)
        | Just target <- [Map.lookup bnd declMap]
        , declKind target /= Boundary
        ]
        ++
        [ Diagnostic Error "V008"
            ("bind right-hand side " <> adp <> " is not an adapter")
            (declName d) (Just adp)
        | Just target <- [Map.lookup adp declMap]
        , declKind target /= Adapter
        ]

----------------------------------------------------------------------
-- W001: 未解決の boundary
----------------------------------------------------------------------

-- | W001: adapter による実装が存在しない boundary を警告する。
data UnresolvedBoundaryRule = UnresolvedBoundaryRule
instance PlatRule UnresolvedBoundaryRule where
  ruleCode _ = "W001"
  checkArch _ arch =
    [ Diagnostic Warning "W001"
        ("boundary " <> declName d <> " has no implementing adapter")
        (declName d) Nothing
    | d <- archDecls arch
    , declKind d == Boundary
    , declName d `Set.notMember` implementedBoundaries
    ]
    where
      implementedBoundaries = Set.fromList
        [ bndName
        | ad <- archDecls arch
        , declKind ad == Adapter
        , Just bndName <- [findImplements (declBody ad)]
        ]

----------------------------------------------------------------------
-- W002: 未定義型名
----------------------------------------------------------------------

-- | W002: 宣言内で参照されている型名が未定義の場合に警告する。
-- @Inject@ 内の型参照は外部型として除外される。
data UndefinedTypeRule = UndefinedTypeRule
instance PlatRule UndefinedTypeRule where
  ruleCode _ = "W002"
  checkDecl _ arch d =
    [ Diagnostic Warning "W002"
        ("type " <> name <> " is not defined")
        (declName d) (Just name)
    | name <- collectTypeRefs d
    , name `Set.notMember` knownTypes
    ]
    where
      knownTypes = Set.fromList $
        -- model / boundary / operation names
        [declName dd | dd <- archDecls arch]
        -- type aliases
        ++ [aliasName ta | ta <- archTypes arch]
        -- registered custom types
        ++ archCustomTypes arch
        -- reserved types
        ++ reservedTypes

      reservedTypes :: [Text]
      reservedTypes = ["Error", "Id"]

-- | 宣言内の TypeExpr から TRef 名を収集（Inject 内は除外）
collectTypeRefs :: Declaration -> [Text]
collectTypeRefs d = concatMap itemRefs (declBody d)
  where
    itemRefs (Field _ ty)    = typeRefs ty
    itemRefs (Op _ ins outs) = concatMap (typeRefs . paramType) (ins ++ outs)
    itemRefs (Input _ ty)    = typeRefs ty
    itemRefs (Output _ ty)   = typeRefs ty
    itemRefs (Inject _ _)    = []  -- ext types are excluded
    itemRefs _               = []

    typeRefs :: TypeExpr -> [Text]
    typeRefs (TBuiltin _)     = []
    typeRefs (TRef name)      = [name]
    typeRefs (TGeneric _ args) = concatMap typeRefs args
    typeRefs (TNullable t)    = typeRefs t

----------------------------------------------------------------------
-- V009: 宣言名の一意性
----------------------------------------------------------------------

-- | V009: 同名の宣言が複数存在する場合の検出。
data UniqueNameRule = UniqueNameRule
instance PlatRule UniqueNameRule where
  ruleCode _ = "V009"
  checkArch _ arch =
    [ Diagnostic Error "V009"
        ("duplicate declaration name: " <> name)
        name Nothing
    | (name, count) <- Map.toList nameCounts
    , count > (1 :: Int)
    ]
    where
      nameCounts = Map.fromListWith (+)
        [(declName d, 1) | d <- archDecls arch]

----------------------------------------------------------------------
-- W003: adapter の多重 implements
----------------------------------------------------------------------

-- | W003: adapter に複数の @implements@ が存在する場合の警告。
-- 最後の値のみが有効になる (last-write-wins)。
data MultipleImplementsRule = MultipleImplementsRule
instance PlatRule MultipleImplementsRule where
  ruleCode _ = "W003"
  checkDecl _ _ d
    | declKind d == Adapter
    , let impls = [name | Implements name <- declBody d]
    , length impls > 1
    = [ Diagnostic Warning "W003"
          ("adapter " <> declName d <> " has multiple implements: "
           <> T.intercalate ", " impls <> "; only the last is used")
          (declName d) Nothing
      ]
    | otherwise = []

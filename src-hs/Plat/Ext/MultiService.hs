-- | Multi-service extension: service boundaries, system composition, cross-service validation.
--
-- Multiple 'Architecture' values (each representing a service) are composed
-- into a unified 'Architecture' via the 'system' builder. Each declaration is
-- tagged with its origin service, and cross-service validation rules ensure
-- that only public API boundaries are referenced across service boundaries.
--
-- @
-- -- Mark a boundary as public API:
-- orderRepo = boundary "OrderRepository" interface $ do
--   serviceApi
--   op "save" [...]
--
-- -- Compose multiple services:
-- platform = system "platform" $ do
--   include "order"   orderService
--   include "payment" paymentService
-- @
module Plat.Ext.MultiService
  ( -- * Extension identity
    multiService
  , multiServiceApi

    -- * Service API marker
  , serviceApi

    -- * System builder
  , SystemBuilder
  , system
  , include
  , serviceRequires

    -- * Queries
  , isServiceApi
  , originService
  , serviceApis
  , serviceDeps

    -- * Rules
  , multiServiceRules
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Set as Set

import Plat.Core.Types
import Plat.Core.Builder (DeclWriter)
import Plat.Core.Algebra (mergeAll, Conflict)
import Plat.Core.Meta
import Plat.Check.Class

----------------------------------------------------------------------
-- Extension identity
----------------------------------------------------------------------

-- | Extension identifier for multi-service.
multiService :: ExtId
multiService = extId "multiservice"

-- | Kind tag for public API boundaries.
multiServiceApi :: MetaTag
multiServiceApi = kind multiService "api"

----------------------------------------------------------------------
-- Service API marker
----------------------------------------------------------------------

-- | Mark a boundary as a public service API. Only boundaries tagged with
-- 'serviceApi' should be referenced by other services.
serviceApi :: DeclWriter 'Boundary ()
serviceApi = tagAs multiServiceApi

----------------------------------------------------------------------
-- Queries
----------------------------------------------------------------------

-- | Check if a declaration is a public service API boundary.
isServiceApi :: Declaration -> Bool
isServiceApi = isTagged multiServiceApi

-- | Get the origin service name of a declaration (set by 'system').
originService :: Declaration -> Maybe Text
originService = lookupAttr multiService "origin"

-- | List all public API boundaries with their origin service.
serviceApis :: Architecture -> [(Text, Declaration)]
serviceApis a =
  [ (svc, d)
  | d <- archDecls a
  , isServiceApi d
  , Just svc <- [originService d]
  ]

-- | Derive the service dependency graph from needs relations and origin tags.
-- Returns a list of (fromService, toService) pairs.
serviceDeps :: Architecture -> [(Text, Text)]
serviceDeps a = Set.toList deps
  where
    originMap = [(declName d, svc) | d <- archDecls a, Just svc <- [originService d]]
    lookupOrigin name = lookup name originMap
    deps = Set.fromList
      [ (fromSvc, toSvc)
      | d <- archDecls a
      , Just fromSvc <- [originService d]
      , Needs target <- declBody d
      , Just toSvc <- [lookupOrigin target]
      , fromSvc /= toSvc
      ]

----------------------------------------------------------------------
-- System builder
----------------------------------------------------------------------

data SystemBuild = SystemBuild
  { sbServices    :: [(Text, Architecture)]  -- reversed
  , sbRelations   :: [Relation]              -- reversed
  }

-- | Builder monad for composing multiple services into a system.
newtype SystemBuilder a = SystemBuilder (SystemBuild -> (a, SystemBuild))

instance Functor SystemBuilder where
  fmap f (SystemBuilder g) = SystemBuilder $ \s -> let (a, s') = g s in (f a, s')

instance Applicative SystemBuilder where
  pure a = SystemBuilder $ \s -> (a, s)
  SystemBuilder f <*> SystemBuilder g = SystemBuilder $ \s ->
    let (ab, s')  = f s
        (a,  s'') = g s'
    in  (ab a, s'')

instance Monad SystemBuilder where
  SystemBuilder g >>= f = SystemBuilder $ \s ->
    let (a, s')        = g s
        SystemBuilder h = f a
    in  h s'

emptySB :: SystemBuild
emptySB = SystemBuild [] []

-- | Include a service's architecture in the system.
include :: Text -> Architecture -> SystemBuilder ()
include name a = SystemBuilder $ \s ->
  ((), s { sbServices = (name, a) : sbServices s })

-- | Declare an explicit cross-service dependency. Service @from@ depends on
-- service @to@ via boundary @boundaryName@. This is optional — dependencies
-- are also inferred from 'needs' relations.
serviceRequires :: Text -> Text -> Text -> SystemBuilder ()
serviceRequires from to boundaryName = SystemBuilder $ \s ->
  let rel = Relation
        { relKind   = "service-requires"
        , relSource = from
        , relTarget = boundaryName
        , relMeta   = [ ("plat-multiservice:from-service", from)
                      , ("plat-multiservice:to-service", to)
                      ]
        }
  in ((), s { sbRelations = rel : sbRelations s })

-- | Compose multiple services into a unified 'Architecture'.
--
-- Each declaration is tagged with its origin service. The result is a
-- standard 'Architecture' that works with all existing tools.
system :: Text -> SystemBuilder () -> Either [Conflict] Architecture
system name (SystemBuilder f) =
  let ((), sb) = f emptySB
      services = reverse (sbServices sb)
      taggedArchs = [tagWithOrigin svcName a | (svcName, a) <- services]
  in case mergeAll name taggedArchs of
    Left cs -> Left cs
    Right merged -> Right merged
      { archRelations = archRelations merged ++ reverse (sbRelations sb)
      }

-- Tag all declarations in an architecture with origin service.
tagWithOrigin :: Text -> Architecture -> Architecture
tagWithOrigin svcName a = a
  { archDecls = map addOrigin (archDecls a) }
  where
    originKey = "plat-multiservice:origin"
    addOrigin d = d { declMeta = (originKey, svcName) : declMeta d }

----------------------------------------------------------------------
-- Rules
----------------------------------------------------------------------

-- | SVC-V001: Cross-service needs must target serviceApi boundaries.
--
-- If an operation in service A needs a boundary from service B, that
-- boundary must be marked with 'serviceApi'.
data CrossServiceApiRule = CrossServiceApiRule
instance PlatRule CrossServiceApiRule where
  ruleCode _ = "SVC-V001"
  checkDecl _ a d
    | declKind d == Operation
    , Just fromSvc <- originService d
    = [ Diagnostic Error "SVC-V001"
          ( declName d <> " (service " <> fromSvc
            <> ") needs " <> target
            <> " from service " <> toSvc
            <> " but it is not marked as serviceApi" )
          (declName d) (Just target)
      | Needs target <- declBody d
      , Just targetDecl <- [findDecl target a]
      , Just toSvc <- [originService targetDecl]
      , fromSvc /= toSvc
      , not (isServiceApi targetDecl)
      ]
    | otherwise = []

-- | SVC-V002: No circular service dependencies.
data ServiceCycleRule = ServiceCycleRule
instance PlatRule ServiceCycleRule where
  ruleCode _ = "SVC-V002"
  checkArch _ a
    | null cycles = []
    | otherwise   = map toDiag cycles
    where
      deps = serviceDeps a
      services = Set.toList (Set.fromList (map fst deps <> map snd deps))
      cycles = findCycles services deps
      toDiag cycle_ = Diagnostic Error "SVC-V002"
        ("circular service dependency: " <> T.intercalate " → " cycle_)
        (case cycle_ of { (c:_) -> c; [] -> "" }) Nothing

-- | SVC-W001: Warning when a non-boundary declaration is referenced cross-service.
data CrossServiceModelRule = CrossServiceModelRule
instance PlatRule CrossServiceModelRule where
  ruleCode _ = "SVC-W001"
  checkArch _ a =
    [ Diagnostic Warning "SVC-W001"
        ( "type " <> refName <> " (service " <> toSvc
          <> ") is referenced from service " <> fromSvc )
        refName Nothing
    | d <- archDecls a
    , Just fromSvc <- [originService d]
    , refName <- extractTypeRefs d
    , Just refDecl <- [findDecl refName a]
    , Just toSvc <- [originService refDecl]
    , fromSvc /= toSvc
    , declKind refDecl == Model
    ]

-- | Multi-service validation rules.
multiServiceRules :: [SomeRule]
multiServiceRules =
  [ SomeRule CrossServiceApiRule
  , SomeRule ServiceCycleRule
  , SomeRule CrossServiceModelRule
  ]

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

findDecl :: Text -> Architecture -> Maybe Declaration
findDecl name a = case filter (\d -> declName d == name) (archDecls a) of
  (d:_) -> Just d
  []    -> Nothing

-- Extract type reference names from a declaration's fields, inputs, outputs, injects.
extractTypeRefs :: Declaration -> [Text]
extractTypeRefs d = concatMap itemRefs (declBody d)
  where
    itemRefs (Field _ ty)    = typeRefNames ty
    itemRefs (Input _ ty)    = typeRefNames ty
    itemRefs (Output _ ty)   = typeRefNames ty
    itemRefs (Op _ ins outs) = concatMap (typeRefNames . paramType) ins
                            ++ concatMap (typeRefNames . paramType) outs
    itemRefs _               = []

    typeRefNames (TRef name)      = [name]
    typeRefNames (TGeneric _ ts)  = concatMap typeRefNames ts
    typeRefNames (TNullable t)    = typeRefNames t
    typeRefNames _                = []

-- Simple DFS cycle detection on a directed graph.
findCycles :: [Text] -> [(Text, Text)] -> [[Text]]
findCycles nodes edges = go Set.empty Set.empty [] nodes
  where
    adj node = [to | (from, to) <- edges, from == node]

    go _ _ acc [] = acc
    go visited inStack acc (n:ns)
      | n `Set.member` visited = go visited inStack acc ns
      | otherwise =
          let (cycles, visited', inStack') = dfs n visited inStack [n]
          in go visited' inStack' (cycles ++ acc) ns

    dfs node visited inStack path_ =
      let visited' = Set.insert node visited
          inStack' = Set.insert node inStack
          neighbors = adj node
          (cycles, v, s) = foldNeighbors neighbors visited' inStack' path_ []
      in (cycles, v, Set.delete node s)

    foldNeighbors [] v s _ acc = (acc, v, s)
    foldNeighbors (n:ns) v s path_ acc
      | n `Set.member` s =
          -- Found cycle: extract from the point where n first appeared
          let cycleNodes = dropWhile (/= n) path_ ++ [n]
          in foldNeighbors ns v s path_ (cycleNodes : acc)
      | n `Set.member` v = foldNeighbors ns v s path_ acc
      | otherwise =
          let (cycles, v', s') = dfs n v s (path_ ++ [n])
          in foldNeighbors ns v' s' path_ (cycles ++ acc)

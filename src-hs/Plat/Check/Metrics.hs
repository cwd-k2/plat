-- | アーキテクチャ品質メトリクス (Martin's dependency metrics)。
--
-- Robert C. Martin のパッケージ結合度メトリクスを Architecture レベルで計算する。
--
-- @
-- let m = metrics arch
-- metricsInstability m "OrderRepository"   -- Ce / (Ca + Ce)
-- metricsAbstractness m                    -- Boundary 数 / 全宣言数
-- metricsHealth m "OrderRepository"        -- |A + I - 1| (Distance from Main Sequence)
-- @
module Plat.Check.Metrics
  ( Metrics (..)
  , DeclMetrics (..)
  , metrics
  , metricsFor
  ) where

import Data.Text (Text)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import Plat.Core.Types
import Plat.Core.Relation (relations)

-- | 全宣言のメトリクス集約。
data Metrics = Metrics
  { mDeclMetrics  :: Map.Map Text DeclMetrics
  , mAbstractness :: Double  -- ^ 全体の抽象度 (Boundary 比率)
  } deriving stock (Show)

-- | 個別宣言のメトリクス。
data DeclMetrics = DeclMetrics
  { dmCa          :: Int     -- ^ Afferent coupling (入力依存数)
  , dmCe          :: Int     -- ^ Efferent coupling (出力依存数)
  , dmInstability :: Double  -- ^ Ce / (Ca + Ce)。Ca + Ce = 0 なら 0
  , dmDistance     :: Double  -- ^ |A + I - 1| (Distance from Main Sequence)
  } deriving stock (Show)

-- | Architecture 全体のメトリクスを計算する。
metrics :: Architecture -> Metrics
metrics a = Metrics
    { mDeclMetrics  = Map.map (toDeclMetrics abstractness) coupling
    , mAbstractness = abstractness
    }
  where
    decls = archDecls a
    declNames = Set.fromList [declName d | d <- decls]
    rels = [ (relSource r, relTarget r)
           | r <- relations a
           , relSource r `Set.member` declNames
           , relTarget r `Set.member` declNames
           , relSource r /= relTarget r
           ]

    -- Efferent: 自分から出る依存先の数
    ceMap = Map.fromListWith Set.union
      [(s, Set.singleton t) | (s, t) <- rels]
    -- Afferent: 自分に来る依存元の数
    caMap = Map.fromListWith Set.union
      [(t, Set.singleton s) | (s, t) <- rels]

    coupling = Map.fromList
      [ (declName d, (Set.size (Map.findWithDefault Set.empty (declName d) caMap)
                     ,Set.size (Map.findWithDefault Set.empty (declName d) ceMap)))
      | d <- decls
      ]

    boundaryCount = length [d | d <- decls, declKind d == Boundary]
    totalCount = length decls
    abstractness = if totalCount == 0 then 0
                   else fromIntegral boundaryCount / fromIntegral totalCount

    toDeclMetrics abst (ca, ce) =
      let instability = if ca + ce == 0 then 0
                        else fromIntegral ce / fromIntegral (ca + ce)
      in DeclMetrics
        { dmCa = ca
        , dmCe = ce
        , dmInstability = instability
        , dmDistance = abs (abst + instability - 1.0)
        }

-- | 指定宣言のメトリクスを取得する。
metricsFor :: Text -> Metrics -> Maybe DeclMetrics
metricsFor name m = Map.lookup name (mDeclMetrics m)

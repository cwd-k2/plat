-- | 拡張メタ DSL。
--
-- 生の @meta@ キー・値ペアに対する型付きヘルパーを提供し、
-- 名前空間の一貫性を保証してマジックストリングを排除する。
--
-- 拡張メタは4つのパターンで全てをカバーする:
--
-- 1. 種別タグ — 宣言を分類する (@tagAs@, @isTagged@)
-- 2. 属性 — 単純なキー・値ペア (@attr@, @lookupAttr@)
-- 3. 注釈 — 名前付きサブキー (@annotate@, @annotations@)
-- 4. 参照 — 他の宣言へのリンク (@refer@, @references@)
module Plat.Core.Meta
  ( -- * 拡張識別子
    ExtId
  , extId

    -- * 種別タグ
  , MetaTag
  , kind
  , tagAs
  , isTagged

    -- * 属性（単純キー・値）
  , attr
  , lookupAttr

    -- * 注釈（名前付きサブキー）
  , annotate
  , annotations

    -- * 他宣言への参照
  , refer
  , references
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import Plat.Core.Types
import Plat.Core.Builder (DeclWriter, meta)

----------------------------------------------------------------------
-- 拡張識別子
----------------------------------------------------------------------

-- | 拡張識別子。全メタキーを @plat-{id}:@ で名前空間化する。
newtype ExtId = ExtId Text
  deriving stock (Show, Eq)

-- | 拡張識別子を生成する。
extId :: Text -> ExtId
extId = ExtId

----------------------------------------------------------------------
-- 種別タグ
----------------------------------------------------------------------

-- | 拡張ドメイン内で宣言を分類する種別タグ。
data MetaTag = MetaTag ExtId Text
  deriving stock (Show, Eq)

-- | 種別タグを定義する。
kind :: ExtId -> Text -> MetaTag
kind = MetaTag

-- | 現在の宣言に種別タグを付与する。
tagAs :: MetaTag -> DeclWriter k ()
tagAs (MetaTag (ExtId ext) val) = meta ("plat-" <> ext <> ":kind") val

-- | 宣言が指定の種別タグを持つか検査する。
isTagged :: MetaTag -> Declaration -> Bool
isTagged (MetaTag (ExtId ext) val) d =
  lookupMeta ("plat-" <> ext <> ":kind") d == Just val

----------------------------------------------------------------------
-- 属性
----------------------------------------------------------------------

-- | 現在の宣言に属性を設定する。
attr :: ExtId -> Text -> Text -> DeclWriter k ()
attr (ExtId ext) key val = meta ("plat-" <> ext <> ":" <> key) val

-- | 属性を検索する。
lookupAttr :: ExtId -> Text -> Declaration -> Maybe Text
lookupAttr (ExtId ext) key = lookupMeta ("plat-" <> ext <> ":" <> key)

----------------------------------------------------------------------
-- 注釈
----------------------------------------------------------------------

-- | カテゴリ配下に名前付き注釈を追加する。
annotate :: ExtId -> Text -> Text -> Text -> DeclWriter k ()
annotate (ExtId ext) cat name val =
  meta ("plat-" <> ext <> ":" <> cat <> ":" <> name) val

-- | カテゴリ内の全注釈を取得する。@[(名前, 値)]@ を返す。
annotations :: ExtId -> Text -> Declaration -> [(Text, Text)]
annotations (ExtId ext) cat d =
  [ (T.drop (T.length pfx) k, v)
  | (k, v) <- declMeta d
  , pfx `T.isPrefixOf` k
  ]
  where pfx = "plat-" <> ext <> ":" <> cat <> ":"

----------------------------------------------------------------------
-- 参照
----------------------------------------------------------------------

-- | 他の宣言への参照を記録する。
refer :: ExtId -> Text -> Decl j -> DeclWriter k ()
refer ext cat (Decl d) = annotate ext cat (declName d) (declName d)

-- | カテゴリ内の全参照を取得する。宣言名のリストを返す。
references :: ExtId -> Text -> Declaration -> [Text]
references ext cat d = map snd (annotations ext cat d)

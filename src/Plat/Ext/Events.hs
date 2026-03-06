-- | Events 拡張: event, emit, on_, apply_
module Plat.Ext.Events
  ( event
  , emit
  , on_
  , apply_
  , eventsRules
  ) where

import Data.Text (Text)

import Plat.Core.Types
import Plat.Core.Builder
import Plat.Check.Class

-- | ドメインイベント（model として表現）
event :: Text -> LayerDef -> DeclWriter 'Model () -> Decl 'Model
event name ly body = model name ly $ do
  meta "plat-events:kind" "event"
  body

-- | イベントの発行を宣言（operation コンテキスト）
emit :: Decl 'Model -> DeclWriter 'Operation ()
emit (Decl d) = meta ("plat-events:emit:" <> declName d) (declName d)

-- | イベントハンドラ（operation として表現）
on_ :: Text -> Decl 'Model -> LayerDef -> DeclWriter 'Operation () -> Decl 'Operation
on_ name evt ly body = operation name ly $ do
  meta "plat-events:kind" "handler"
  meta "plat-events:on" (declName (unDecl evt))
  body

-- | イベントの適用を宣言（model コンテキスト、aggregate で使用）
apply_ :: Decl 'Model -> DeclWriter 'Model ()
apply_ (Decl d) = meta ("plat-events:apply:" <> declName d) (declName d)

eventsRules :: [SomeRule]
eventsRules = []

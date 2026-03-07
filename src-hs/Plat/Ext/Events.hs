-- | Events extension: event, emit, on_, apply_
module Plat.Ext.Events
  ( event
  , emit
  , on_
  , apply_
  , eventsRules
  -- * Meta vocabulary
  , events
  , evtEvent
  , evtHandler
  ) where

import Data.Text (Text)

import Plat.Core.Types
import Plat.Core.Builder
import Plat.Core.Meta
import Plat.Check.Class

-- | Events extension identifier
events :: ExtId
events = extId "events"

-- | Events メタタグ: event / handler
evtEvent, evtHandler :: MetaTag
evtEvent   = kind events "event"
evtHandler = kind events "handler"

-- | Domain event (model)
event :: Text -> LayerDef -> DeclWriter 'Model () -> Decl 'Model
event name ly body = model name ly $ do
  tagAs evtEvent
  body

-- | Emit an event (operation context)
emit :: Decl 'Model -> DeclWriter 'Operation ()
emit = refer events "emit"

-- | Event handler (operation)
on_ :: Text -> Decl 'Model -> LayerDef -> DeclWriter 'Operation () -> Decl 'Operation
on_ name evt ly body = operation name ly $ do
  tagAs evtHandler
  attr events "on" (declName (unDecl evt))
  body

-- | Apply an event (model context, for aggregates)
apply_ :: Decl 'Model -> DeclWriter 'Model ()
apply_ = refer events "apply"

-- | Events 拡張の検証ルール一覧 (現在は空)
eventsRules :: [SomeRule]
eventsRules = []

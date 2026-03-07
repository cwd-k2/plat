-- | Events extension: event, emit, on_, apply
module Plat.Ext.Events
  ( event
  , emit
  , on_
  , apply
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

import qualified Data.Set as Set

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
apply :: Decl 'Model -> DeclWriter 'Model ()
apply = refer events "apply"

----------------------------------------------------------------------
-- Events Rules
----------------------------------------------------------------------

-- | EVT-V001: emit で参照されたイベントが Architecture 内に存在すること
data EmitTargetExistsRule = EmitTargetExistsRule
instance PlatRule EmitTargetExistsRule where
  ruleCode _ = "EVT-V001"
  checkDecl _ arch d =
    [ Diagnostic Error "EVT-V001"
        ("operation " <> declName d <> " emits unknown event " <> evtName)
        (declName d) (Just evtName)
    | evtName <- references events "emit" d
    , evtName `Set.notMember` declNames
    ]
    where declNames = Set.fromList [declName dd | dd <- archDecls arch]

-- | EVT-W001: on_ ハンドラの対象イベントが Architecture 内に存在すること
data HandlerTargetExistsRule = HandlerTargetExistsRule
instance PlatRule HandlerTargetExistsRule where
  ruleCode _ = "EVT-W001"
  checkDecl _ arch d
    | isTagged evtHandler d
    , Just evtName <- lookupAttr events "on" d
    , evtName `Set.notMember` declNames
    = [ Diagnostic Warning "EVT-W001"
          ("handler " <> declName d <> " targets unknown event " <> evtName)
          (declName d) (Just evtName)
      ]
    | otherwise = []
    where declNames = Set.fromList [declName dd | dd <- archDecls arch]

-- | Events 拡張の検証ルール一覧
eventsRules :: [SomeRule]
eventsRules =
  [ SomeRule EmitTargetExistsRule
  , SomeRule HandlerTargetExistsRule
  ]

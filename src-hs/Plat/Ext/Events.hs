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
  checkDecl _ a d =
    [ Diagnostic Error "EVT-V001"
        ("operation " <> declName d <> " emits unknown event " <> evtName)
        (declName d) (Just evtName)
    | evtName <- references events "emit" d
    , evtName `Set.notMember` declNames
    ]
    where declNames = Set.fromList [declName dd | dd <- archDecls a]

-- | EVT-W001: on_ ハンドラの対象イベントが Architecture 内に存在すること
data HandlerTargetExistsRule = HandlerTargetExistsRule
instance PlatRule HandlerTargetExistsRule where
  ruleCode _ = "EVT-W001"
  checkDecl _ a d
    | isTagged evtHandler d
    , Just evtName <- lookupAttr events "on" d
    , evtName `Set.notMember` declNames
    = [ Diagnostic Warning "EVT-W001"
          ("handler " <> declName d <> " targets unknown event " <> evtName)
          (declName d) (Just evtName)
      ]
    | otherwise = []
    where declNames = Set.fromList [declName dd | dd <- archDecls a]

-- | EVT-W002: emit されたイベントに対応する handler が存在しない
data UnhandledEventRule = UnhandledEventRule
instance PlatRule UnhandledEventRule where
  ruleCode _ = "EVT-W002"
  checkArch _ a =
    [ Diagnostic Warning "EVT-W002"
        ("event " <> evtName <> " is emitted but has no handler")
        evtName Nothing
    | evtName <- Set.toList emittedEvents
    , evtName `Set.notMember` handledEvents
    ]
    where
      emittedEvents = Set.fromList
        [ e | d <- archDecls a, e <- references events "emit" d ]
      handledEvents = Set.fromList
        [ e | d <- archDecls a, isTagged evtHandler d
            , Just e <- [lookupAttr events "on" d] ]

-- | Events 拡張の検証ルール一覧
eventsRules :: [SomeRule]
eventsRules =
  [ SomeRule EmitTargetExistsRule
  , SomeRule HandlerTargetExistsRule
  , SomeRule UnhandledEventRule
  ]

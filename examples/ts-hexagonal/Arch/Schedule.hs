module Arch.Schedule
  ( scheduleStore
  , scheduleNotification
  , processPendingSchedules
  , cancelSchedule
  , inMemoryScheduleStore
  , declareAll
  ) where

import Plat.Core
import Arch.Layers       (app, port_, adp)
import Arch.Domain       (schedule, priority)
import Arch.Notification (templateStore, notificationSender, notificationLog)

----------------------------------------------------------------------
-- Port
----------------------------------------------------------------------

scheduleStore :: Decl 'Boundary
scheduleStore = boundary "ScheduleStore" port_ $ do
  op "save"          ["schedule" .: ref schedule] ["err" .: error_]
  op "findPending"   [] ["schedules" .: list (ref schedule), "err" .: error_]
  op "markExecuted"  ["id" .: string] ["err" .: error_]
  op "cancel"        ["id" .: string] ["err" .: error_]

----------------------------------------------------------------------
-- Use cases
----------------------------------------------------------------------

scheduleNotification :: Decl 'Operation
scheduleNotification = operation "ScheduleNotification" app $ do
  input  "recipientId" string
  input  "templateId"  string
  input  "vars"        (mapType string string)
  input  "priority"    (ref priority)
  input  "scheduledAt" dateTime
  output "scheduleId"  string
  output "err"         error_
  needs scheduleStore
  needs templateStore

processPendingSchedules :: Decl 'Operation
processPendingSchedules = operation "ProcessPendingSchedules" app $ do
  output "processed" int
  output "failed"    int
  output "err"       error_
  needs scheduleStore
  needs notificationSender
  needs notificationLog

cancelSchedule :: Decl 'Operation
cancelSchedule = operation "CancelSchedule" app $ do
  input  "scheduleId" string
  output "err"        error_
  needs scheduleStore

----------------------------------------------------------------------
-- Adapter
----------------------------------------------------------------------

inMemoryScheduleStore :: Decl 'Adapter
inMemoryScheduleStore = adapter "InMemoryScheduleStore" adp $ do
  implements scheduleStore
  inject "store" (ext "Map")

----------------------------------------------------------------------
-- Declare all
----------------------------------------------------------------------

declareAll :: ArchBuilder ()
declareAll = do
  declare scheduleStore
  declare scheduleNotification
  declare processPendingSchedules
  declare cancelSchedule
  declare inMemoryScheduleStore

-- | Example: TypeScript Hexagonal Architecture — Notification Service
--
-- Demonstrates plat-hs with Core API + DDD enum.
-- Target language: TypeScript
module Main where

import qualified Data.Text.IO as TIO

import Plat.Core
import Plat.Check
import Plat.Generate.Mermaid  (renderMermaid)
import Plat.Generate.Markdown (renderMarkdown)
import Plat.Ext.DDD           (enum_)

----------------------------------------------------------------------
-- Layers (hexagonal: domain at core, ports around, adapters outside)
----------------------------------------------------------------------

dom :: LayerDef
dom = layer "domain"

app :: LayerDef
app = layer "application" `depends` [dom, port_]

port_ :: LayerDef
port_ = layer "port" `depends` [dom]

adp :: LayerDef
adp = layer "adapter" `depends` [dom, port_, app]

----------------------------------------------------------------------
-- Domain models
----------------------------------------------------------------------

channel :: Decl 'Model
channel = enum_ "Channel" dom ["Email", "SMS", "Push", "Slack"]

priority :: Decl 'Model
priority = enum_ "Priority" dom ["Low", "Normal", "High", "Critical"]

recipient :: Decl 'Model
recipient = model "Recipient" dom $ do
  field "id"      string
  field "name"    string
  field "email"   (nullable string)
  field "phone"   (nullable string)
  field "channel" (ref channel)

template :: Decl 'Model
template = model "Template" dom $ do
  field "id"       string
  field "name"     string
  field "subject"  string
  field "body"     string
  field "channel"  (ref channel)
  field "vars"     (list string)

notification :: Decl 'Model
notification = model "Notification" dom $ do
  field "id"         string
  field "recipient"  (ref recipient)
  field "template"   (ref template)
  field "channel"    (ref channel)
  field "priority"   (ref priority)
  field "vars"       (mapType string string)
  field "sentAt"     (nullable dateTime)
  field "status"     string

scheduleStatus :: Decl 'Model
scheduleStatus = enum_ "ScheduleStatus" dom ["Pending", "Executed", "Cancelled", "Failed"]

schedule :: Decl 'Model
schedule = model "Schedule" dom $ do
  field "id"          string
  field "recipientId" string
  field "templateId"  string
  field "vars"        (mapType string string)
  field "priority"    (ref priority)
  field "scheduledAt" dateTime
  field "executedAt"  (nullable dateTime)
  field "status"      (ref scheduleStatus)

userPreference :: Decl 'Model
userPreference = model "UserPreference" dom $ do
  field "userId"           string
  field "preferredChannel" (ref channel)
  field "enabled"          bool
  field "quietStart"       (nullable string)
  field "quietEnd"         (nullable string)

deliveryStatus :: Decl 'Model
deliveryStatus = enum_ "DeliveryStatus" dom ["Pending", "Delivered", "Failed", "Bounced"]

deliveryReport :: Decl 'Model
deliveryReport = model "DeliveryReport" dom $ do
  field "id"             string
  field "notificationId" string
  field "channel"        (ref channel)
  field "status"         (ref deliveryStatus)
  field "deliveredAt"    (nullable dateTime)
  field "errorMessage"   (nullable string)

----------------------------------------------------------------------
-- Ports (driven / driving)
----------------------------------------------------------------------

notificationSender :: Decl 'Boundary
notificationSender = boundary "NotificationSender" port_ $ do
  op "send" ["notification" .: ref notification] ["err" .: error_]

templateStore :: Decl 'Boundary
templateStore = boundary "TemplateStore" port_ $ do
  op "find"    ["id" .: string] ["template" .: ref template, "err" .: error_]
  op "findAll" [] ["templates" .: list (ref template), "err" .: error_]

notificationLog :: Decl 'Boundary
notificationLog = boundary "NotificationLog" port_ $ do
  op "record"  ["notification" .: ref notification] ["err" .: error_]
  op "history" ["recipientId" .: string] ["notifications" .: list (ref notification), "err" .: error_]

scheduleStore :: Decl 'Boundary
scheduleStore = boundary "ScheduleStore" port_ $ do
  op "save"          ["schedule" .: ref schedule] ["err" .: error_]
  op "findPending"   [] ["schedules" .: list (ref schedule), "err" .: error_]
  op "markExecuted"  ["id" .: string] ["err" .: error_]
  op "cancel"        ["id" .: string] ["err" .: error_]

preferenceStore :: Decl 'Boundary
preferenceStore = boundary "PreferenceStore" port_ $ do
  op "findByUserId" ["userId" .: string] ["pref" .: ref userPreference, "err" .: error_]
  op "save"         ["pref" .: ref userPreference] ["err" .: error_]

deliveryTracker :: Decl 'Boundary
deliveryTracker = boundary "DeliveryTracker" port_ $ do
  op "track"     ["notification" .: ref notification, "channel" .: ref channel, "status" .: ref deliveryStatus] ["err" .: error_]
  op "getReport" ["notificationId" .: string] ["report" .: ref deliveryReport, "err" .: error_]

----------------------------------------------------------------------
-- Application (use cases)
----------------------------------------------------------------------

sendNotification :: Decl 'Operation
sendNotification = operation "SendNotification" app $ do
  input  "recipientId" string
  input  "templateId"  string
  input  "vars"        (mapType string string)
  input  "priority"    (ref priority)
  output "notificationId" string
  output "err"         error_
  needs templateStore
  needs notificationSender
  needs notificationLog

sendBulk :: Decl 'Operation
sendBulk = operation "SendBulkNotification" app $ do
  input  "recipientIds" (list string)
  input  "templateId"   string
  input  "vars"         (mapType string string)
  output "sent"         int
  output "failed"       int
  output "err"          error_
  needs templateStore
  needs notificationSender
  needs notificationLog

getHistory :: Decl 'Operation
getHistory = operation "GetNotificationHistory" app $ do
  input  "recipientId" string
  output "notifications" (list (ref notification))
  output "err"         error_
  needs notificationLog

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

getPreferences :: Decl 'Operation
getPreferences = operation "GetPreferences" app $ do
  input  "userId" string
  output "pref"   (ref userPreference)
  output "err"    error_
  needs preferenceStore

updatePreferences :: Decl 'Operation
updatePreferences = operation "UpdatePreferences" app $ do
  input  "pref" (ref userPreference)
  output "err"  error_
  needs preferenceStore

getDeliveryReport :: Decl 'Operation
getDeliveryReport = operation "GetDeliveryReport" app $ do
  input  "notificationId" string
  output "report"         (ref deliveryReport)
  output "err"            error_
  needs deliveryTracker

----------------------------------------------------------------------
-- Adapters
----------------------------------------------------------------------

emailSender :: Decl 'Adapter
emailSender = adapter "NodemailerSender" adp $ do
  implements notificationSender
  inject "transport" (ext "nodemailer.Transporter")

smsSender :: Decl 'Adapter
smsSender = adapter "TwilioSender" adp $ do
  implements notificationSender
  inject "client" (ext "twilio.Client")

mongoTemplateStore :: Decl 'Adapter
mongoTemplateStore = adapter "MongoTemplateStore" adp $ do
  implements templateStore
  inject "db" (ext "mongodb.Db")

mongoNotificationLog :: Decl 'Adapter
mongoNotificationLog = adapter "MongoNotificationLog" adp $ do
  implements notificationLog
  inject "db" (ext "mongodb.Db")

inMemoryScheduleStore :: Decl 'Adapter
inMemoryScheduleStore = adapter "InMemoryScheduleStore" adp $ do
  implements scheduleStore
  inject "store" (ext "Map")

inMemoryPreferenceStore :: Decl 'Adapter
inMemoryPreferenceStore = adapter "InMemoryPreferenceStore" adp $ do
  implements preferenceStore
  inject "store" (ext "Map")

consoleDeliveryTracker :: Decl 'Adapter
consoleDeliveryTracker = adapter "ConsoleDeliveryTracker" adp $ do
  implements deliveryTracker

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------

emailWiring :: Decl 'Compose
emailWiring = compose "EmailNotificationWiring" $ do
  bind notificationSender emailSender
  bind templateStore      mongoTemplateStore
  bind notificationLog    mongoNotificationLog
  bind scheduleStore      inMemoryScheduleStore
  bind preferenceStore    inMemoryPreferenceStore
  bind deliveryTracker    consoleDeliveryTracker
  entry sendNotification
  entry sendBulk
  entry getHistory
  entry scheduleNotification
  entry processPendingSchedules
  entry cancelSchedule
  entry getPreferences
  entry updatePreferences
  entry getDeliveryReport

smsWiring :: Decl 'Compose
smsWiring = compose "SmsNotificationWiring" $ do
  bind notificationSender smsSender
  bind templateStore      mongoTemplateStore
  bind notificationLog    mongoNotificationLog
  entry sendNotification

----------------------------------------------------------------------
-- Architecture
----------------------------------------------------------------------

architecture :: Architecture
architecture = arch "notification-service" $ do
  useLayers [dom, app, port_, adp]

  -- Domain
  declare channel
  declare priority
  declare recipient
  declare template
  declare notification
  declare scheduleStatus
  declare schedule
  declare userPreference
  declare deliveryStatus
  declare deliveryReport

  -- Ports
  declare notificationSender
  declare templateStore
  declare notificationLog
  declare scheduleStore
  declare preferenceStore
  declare deliveryTracker

  -- Use cases
  declare sendNotification
  declare sendBulk
  declare getHistory
  declare scheduleNotification
  declare processPendingSchedules
  declare cancelSchedule
  declare getPreferences
  declare updatePreferences
  declare getDeliveryReport

  -- Adapters
  declare emailSender
  declare smsSender
  declare mongoTemplateStore
  declare mongoNotificationLog
  declare inMemoryScheduleStore
  declare inMemoryPreferenceStore
  declare consoleDeliveryTracker

  -- Wiring
  declare emailWiring
  declare smsWiring

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

main :: IO ()
main = do
  putStrLn "=== TypeScript Hexagonal: Notification Service ==="
  putStrLn ""

  let checkResult = check architecture
  TIO.putStrLn $ prettyCheck checkResult
  putStrLn ""

  putStrLn "--- Mermaid ---"
  TIO.putStrLn $ renderMermaid architecture
  putStrLn ""

  putStrLn "--- Markdown ---"
  TIO.putStrLn $ renderMarkdown architecture

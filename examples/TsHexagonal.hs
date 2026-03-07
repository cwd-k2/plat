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

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------

emailWiring :: Decl 'Compose
emailWiring = compose "EmailNotificationWiring" $ do
  bind notificationSender emailSender
  bind templateStore      mongoTemplateStore
  bind notificationLog    mongoNotificationLog
  entry sendNotification
  entry sendBulk
  entry getHistory

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

  -- Ports
  declare notificationSender
  declare templateStore
  declare notificationLog

  -- Use cases
  declare sendNotification
  declare sendBulk
  declare getHistory

  -- Adapters
  declare emailSender
  declare smsSender
  declare mongoTemplateStore
  declare mongoNotificationLog

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

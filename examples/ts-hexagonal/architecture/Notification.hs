module Notification
  ( notificationSender
  , templateStore
  , notificationLog
  , sendNotification
  , sendBulk
  , getHistory
  , emailSender
  , smsSender
  , mongoTemplateStore
  , mongoNotificationLog
  , declareAll
  ) where

import Plat.Core
import Layers  (app, port_, adp)
import Domain  (notification, template, priority)

----------------------------------------------------------------------
-- Ports
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
-- Use cases
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
-- Declare all
----------------------------------------------------------------------

declareAll :: ArchBuilder ()
declareAll = do
  declare notificationSender
  declare templateStore
  declare notificationLog
  declare sendNotification
  declare sendBulk
  declare getHistory
  declare emailSender
  declare smsSender
  declare mongoTemplateStore
  declare mongoNotificationLog

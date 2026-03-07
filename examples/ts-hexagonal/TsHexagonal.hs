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

import Arch.Layers
import qualified Arch.Domain
import qualified Arch.Notification
import qualified Arch.Schedule
import qualified Arch.Preference
import qualified Arch.Delivery

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------

emailWiring :: Decl 'Compose
emailWiring = compose "EmailNotificationWiring" $ do
  bind Arch.Notification.notificationSender Arch.Notification.emailSender
  bind Arch.Notification.templateStore      Arch.Notification.mongoTemplateStore
  bind Arch.Notification.notificationLog    Arch.Notification.mongoNotificationLog
  bind Arch.Schedule.scheduleStore          Arch.Schedule.inMemoryScheduleStore
  bind Arch.Preference.preferenceStore      Arch.Preference.inMemoryPreferenceStore
  bind Arch.Delivery.deliveryTracker        Arch.Delivery.consoleDeliveryTracker
  entry Arch.Notification.sendNotification
  entry Arch.Notification.sendBulk
  entry Arch.Notification.getHistory
  entry Arch.Schedule.scheduleNotification
  entry Arch.Schedule.processPendingSchedules
  entry Arch.Schedule.cancelSchedule
  entry Arch.Preference.getPreferences
  entry Arch.Preference.updatePreferences
  entry Arch.Delivery.getDeliveryReport

smsWiring :: Decl 'Compose
smsWiring = compose "SmsNotificationWiring" $ do
  bind Arch.Notification.notificationSender Arch.Notification.smsSender
  bind Arch.Notification.templateStore      Arch.Notification.mongoTemplateStore
  bind Arch.Notification.notificationLog    Arch.Notification.mongoNotificationLog
  entry Arch.Notification.sendNotification

----------------------------------------------------------------------
-- Architecture
----------------------------------------------------------------------

architecture :: Architecture
architecture = arch "notification-service" $ do
  useLayers [dom, app, port_, adp]
  Arch.Domain.declareAll
  Arch.Notification.declareAll
  Arch.Schedule.declareAll
  Arch.Preference.declareAll
  Arch.Delivery.declareAll
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

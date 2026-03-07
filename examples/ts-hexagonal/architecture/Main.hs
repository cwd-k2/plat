-- | Example: TypeScript Hexagonal Architecture — Notification Service
--
-- Demonstrates plat-hs with Core API + DDD enum.
-- Target language: TypeScript
module Main where

import Data.Text (Text)
import qualified Data.Text.IO as TIO

import Plat.Core
import Plat.Check
import Plat.Verify.Manifest (manifest, renderManifest)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>), takeDirectory)

import Layers
import qualified Domain
import qualified Notification
import qualified Schedule
import qualified Preference
import qualified Delivery

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------

emailWiring :: Decl 'Compose
emailWiring = compose "EmailNotificationWiring" $ do
  bind Notification.notificationSender Notification.emailSender
  bind Notification.templateStore      Notification.mongoTemplateStore
  bind Notification.notificationLog    Notification.mongoNotificationLog
  bind Schedule.scheduleStore          Schedule.inMemoryScheduleStore
  bind Preference.preferenceStore      Preference.inMemoryPreferenceStore
  bind Delivery.deliveryTracker        Delivery.consoleDeliveryTracker
  entry Notification.sendNotification
  entry Notification.sendBulk
  entry Notification.getHistory
  entry Schedule.scheduleNotification
  entry Schedule.processPendingSchedules
  entry Schedule.cancelSchedule
  entry Preference.getPreferences
  entry Preference.updatePreferences
  entry Delivery.getDeliveryReport

smsWiring :: Decl 'Compose
smsWiring = compose "SmsNotificationWiring" $ do
  bind Notification.notificationSender Notification.smsSender
  bind Notification.templateStore      Notification.mongoTemplateStore
  bind Notification.notificationLog    Notification.mongoNotificationLog
  entry Notification.sendNotification

----------------------------------------------------------------------
-- Architecture
----------------------------------------------------------------------

architecture :: Architecture
architecture = arch "notification-service" $ do
  useLayers [dom, app, port_, adp]
  Domain.declareAll
  Notification.declareAll
  Schedule.declareAll
  Preference.declareAll
  Delivery.declareAll
  declare emailWiring
  declare smsWiring

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

out :: FilePath -> Text -> IO ()
out fp content = do
  createDirectoryIfMissing True (takeDirectory fp)
  TIO.writeFile fp content
  putStrLn $ "  wrote " ++ fp

main :: IO ()
main = do
  let dir = "examples/ts-hexagonal/dist"
  putStrLn "=== TypeScript Hexagonal: Notification Service ==="

  out (dir </> "check.txt")         (prettyCheck (check architecture))
  out (dir </> "manifest.json")     (renderManifest (manifest architecture))

  putStrLn "done."

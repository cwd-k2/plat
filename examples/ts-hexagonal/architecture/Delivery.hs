module Delivery
  ( deliveryTracker
  , getDeliveryReport
  , consoleDeliveryTracker
  , declareAll
  ) where

import Plat.Core
import Layers  (app, port_, adp)
import Domain  (notification, channel, deliveryStatus, deliveryReport)

----------------------------------------------------------------------
-- Port
----------------------------------------------------------------------

deliveryTracker :: Decl 'Boundary
deliveryTracker = boundary "DeliveryTracker" port_ $ do
  op "track"     ["notification" .: ref notification, "channel" .: ref channel, "status" .: ref deliveryStatus] ["err" .: error_]
  op "getReport" ["notificationId" .: string] ["report" .: ref deliveryReport, "err" .: error_]

----------------------------------------------------------------------
-- Use case
----------------------------------------------------------------------

getDeliveryReport :: Decl 'Operation
getDeliveryReport = operation "GetDeliveryReport" app $ do
  input  "notificationId" string
  output "report"         (ref deliveryReport)
  output "err"            error_
  needs deliveryTracker

----------------------------------------------------------------------
-- Adapter
----------------------------------------------------------------------

consoleDeliveryTracker :: Decl 'Adapter
consoleDeliveryTracker = adapter "ConsoleDeliveryTracker" adp $ do
  implements deliveryTracker

----------------------------------------------------------------------
-- Declare all
----------------------------------------------------------------------

declareAll :: ArchBuilder ()
declareAll = do
  declare deliveryTracker
  declare getDeliveryReport
  declare consoleDeliveryTracker

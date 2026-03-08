module Domain
  ( channel
  , priority
  , recipient
  , template
  , notification
  , scheduleStatus
  , schedule
  , userPreference
  , deliveryStatus
  , deliveryReport
  , declareAll
  ) where

import Plat.Core
import Plat.Ext.DDD (enum)
import Layers   (dom)

channel :: Decl 'Model
channel = enum "Channel" dom ["Email", "SMS", "Push", "Slack"]

priority :: Decl 'Model
priority = enum "Priority" dom ["Low", "Normal", "High", "Critical"]

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
  field "vars"       (map_ string string)
  field "sentAt"     (nullable dateTime)
  field "status"     string

scheduleStatus :: Decl 'Model
scheduleStatus = enum "ScheduleStatus" dom ["Pending", "Executed", "Cancelled", "Failed"]

schedule :: Decl 'Model
schedule = model "Schedule" dom $ do
  field "id"          string
  field "recipientId" string
  field "templateId"  string
  field "vars"        (map_ string string)
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
deliveryStatus = enum "DeliveryStatus" dom ["Pending", "Delivered", "Failed", "Bounced"]

deliveryReport :: Decl 'Model
deliveryReport = model "DeliveryReport" dom $ do
  field "id"             string
  field "notificationId" string
  field "channel"        (ref channel)
  field "status"         (ref deliveryStatus)
  field "deliveredAt"    (nullable dateTime)
  field "errorMessage"   (nullable string)

-- | ArchBuilder はモナド — declare を do 記法で連ねるだけでよい。
--   declares は動的リスト向け。静的な登録には declare を使う。
declareAll :: ArchBuilder ()
declareAll = do
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

module Arch.Preference
  ( preferenceStore
  , getPreferences
  , updatePreferences
  , inMemoryPreferenceStore
  , declareAll
  ) where

import Plat.Core
import Arch.Layers  (app, port_, adp)
import Arch.Domain  (userPreference)

----------------------------------------------------------------------
-- Port
----------------------------------------------------------------------

preferenceStore :: Decl 'Boundary
preferenceStore = boundary "PreferenceStore" port_ $ do
  op "findByUserId" ["userId" .: string] ["pref" .: ref userPreference, "err" .: error_]
  op "save"         ["pref" .: ref userPreference] ["err" .: error_]

----------------------------------------------------------------------
-- Use cases
----------------------------------------------------------------------

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

----------------------------------------------------------------------
-- Adapter
----------------------------------------------------------------------

inMemoryPreferenceStore :: Decl 'Adapter
inMemoryPreferenceStore = adapter "InMemoryPreferenceStore" adp $ do
  implements preferenceStore
  inject "store" (ext "Map")

----------------------------------------------------------------------
-- Declare all
----------------------------------------------------------------------

declareAll :: ArchBuilder ()
declareAll = do
  declare preferenceStore
  declare getPreferences
  declare updatePreferences
  declare inMemoryPreferenceStore

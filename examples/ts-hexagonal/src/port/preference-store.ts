import type { UserPreference } from "../domain/preference.js";

// Corresponds to: boundary PreferenceStore : port
//   op findByUserId: String -> (UserPreference, Error)
//   op save:         UserPreference -> Error
export interface PreferenceStore {
  findByUserId(userId: string): Promise<UserPreference>;
  save(pref: UserPreference): Promise<void>;
}

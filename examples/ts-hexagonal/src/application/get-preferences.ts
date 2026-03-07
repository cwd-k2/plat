import type { UserPreference } from "../domain/preference.js";
import type { PreferenceStore } from "../port/preference-store.js";

// Corresponds to: operation GetPreferences : application
//   needs PreferenceStore
export class GetPreferences {
  constructor(private preferenceStore: PreferenceStore) {}

  async execute(userId: string): Promise<UserPreference> {
    return this.preferenceStore.findByUserId(userId);
  }
}

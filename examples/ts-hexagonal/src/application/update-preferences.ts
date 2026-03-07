import type { UserPreference } from "../domain/preference.js";
import type { PreferenceStore } from "../port/preference-store.js";

// Corresponds to: operation UpdatePreferences : application
//   needs PreferenceStore
export class UpdatePreferences {
  constructor(private preferenceStore: PreferenceStore) {}

  async execute(pref: UserPreference): Promise<void> {
    await this.preferenceStore.save(pref);
  }
}

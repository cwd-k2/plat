import type { UserPreference } from "../domain/preference.js";
import type { PreferenceStore } from "../port/preference-store.js";

// Corresponds to: adapter InMemoryPreferenceStore : adapter implements PreferenceStore
// In-memory stub for concept verification.
export class InMemoryPreferenceStore implements PreferenceStore {
  private store = new Map<string, UserPreference>();

  async findByUserId(userId: string): Promise<UserPreference> {
    const pref = this.store.get(userId);
    if (!pref) throw new Error(`Preferences for ${userId} not found`);
    return pref;
  }

  async save(pref: UserPreference): Promise<void> {
    this.store.set(pref.userId, pref);
  }
}

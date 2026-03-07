// Domain model for user notification preferences.

import type { Channel } from "./notification.js";

export interface UserPreference {
  userId: string;
  preferredChannel: Channel;
  enabled: boolean;
  quietStart: string | null;
  quietEnd: string | null;
}

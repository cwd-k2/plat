import type { Notification } from "../domain/notification.js";
import type { NotificationLog } from "../port/notification-log.js";

// Corresponds to: adapter MongoNotificationLog : adapter implements NotificationLog
// In-memory stub for concept verification.
export class InMemoryNotificationLog implements NotificationLog {
  private entries: Notification[] = [];

  async record(notification: Notification): Promise<void> {
    this.entries.push(notification);
  }

  async history(recipientId: string): Promise<Notification[]> {
    return this.entries.filter((n) => n.recipient.id === recipientId);
  }
}

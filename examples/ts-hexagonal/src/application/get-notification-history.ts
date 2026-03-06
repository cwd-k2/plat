import type { Notification } from "../domain/notification.js";
import type { NotificationLog } from "../port/notification-log.js";

// Corresponds to: operation GetNotificationHistory : application
//   needs NotificationLog
export class GetNotificationHistory {
  constructor(private log: NotificationLog) {}

  async execute(recipientId: string): Promise<Notification[]> {
    return this.log.history(recipientId);
  }
}

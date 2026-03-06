import type { Notification } from "../domain/notification.js";

// Corresponds to: boundary NotificationSender : port
//   op send: Notification -> Error
export interface NotificationSender {
  send(notification: Notification): Promise<void>;
}

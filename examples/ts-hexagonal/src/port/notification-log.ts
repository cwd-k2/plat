import type { Notification } from "../domain/notification.js";

// Corresponds to: boundary NotificationLog : port
//   op record:  Notification -> Error
//   op history: String -> (List<Notification>, Error)
export interface NotificationLog {
  record(notification: Notification): Promise<void>;
  history(recipientId: string): Promise<Notification[]>;
}

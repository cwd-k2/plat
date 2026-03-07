import type { Notification, Channel } from "../domain/notification.js";
import type { DeliveryStatus, DeliveryReport } from "../domain/delivery.js";

// Corresponds to: boundary DeliveryTracker : port
//   op track:     (Notification, Channel, DeliveryStatus) -> Error
//   op getReport: String -> (DeliveryReport, Error)
export interface DeliveryTracker {
  track(notification: Notification, channel: Channel, status: DeliveryStatus): Promise<void>;
  getReport(notificationId: string): Promise<DeliveryReport>;
}

import type { Notification, Channel } from "../domain/notification.js";
import type { DeliveryStatus, DeliveryReport } from "../domain/delivery.js";
import type { DeliveryTracker } from "../port/delivery-tracker.js";

// Corresponds to: adapter ConsoleDeliveryTracker : adapter implements DeliveryTracker
// Console stub for concept verification — prints to stdout.
export class ConsoleDeliveryTracker implements DeliveryTracker {
  private reports = new Map<string, DeliveryReport>();

  async track(notification: Notification, channel: Channel, status: DeliveryStatus): Promise<void> {
    const report: DeliveryReport = {
      id: crypto.randomUUID(),
      notificationId: notification.id,
      channel,
      status,
      deliveredAt: status === "Delivered" ? new Date() : null,
      errorMessage: null,
    };
    this.reports.set(notification.id, report);
    console.log(
      `[delivery] ${notification.id} via ${channel}: ${status}`,
    );
  }

  async getReport(notificationId: string): Promise<DeliveryReport> {
    const report = this.reports.get(notificationId);
    if (!report) throw new Error(`No delivery report for ${notificationId}`);
    return report;
  }
}

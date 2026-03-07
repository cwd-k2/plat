import type { DeliveryReport } from "../domain/delivery.js";
import type { DeliveryTracker } from "../port/delivery-tracker.js";

// Corresponds to: operation GetDeliveryReport : application
//   needs DeliveryTracker
export class GetDeliveryReport {
  constructor(private deliveryTracker: DeliveryTracker) {}

  async execute(notificationId: string): Promise<DeliveryReport> {
    return this.deliveryTracker.getReport(notificationId);
  }
}

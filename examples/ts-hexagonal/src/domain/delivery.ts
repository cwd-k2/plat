// Domain models for delivery tracking.

import type { Channel } from "./notification.js";

export type DeliveryStatus = "Pending" | "Delivered" | "Failed" | "Bounced";

export interface DeliveryReport {
  id: string;
  notificationId: string;
  channel: Channel;
  status: DeliveryStatus;
  deliveredAt: Date | null;
  errorMessage: string | null;
}

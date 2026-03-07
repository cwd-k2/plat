// Domain models for scheduling.

import type { Priority } from "./notification.js";

export type ScheduleStatus = "Pending" | "Executed" | "Cancelled" | "Failed";

export interface Schedule {
  id: string;
  recipientId: string;
  templateId: string;
  vars: Map<string, string>;
  priority: Priority;
  scheduledAt: Date;
  executedAt: Date | null;
  status: ScheduleStatus;
}

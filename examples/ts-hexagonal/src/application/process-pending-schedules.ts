import type { ScheduleStore } from "../port/schedule-store.js";
import type { NotificationSender } from "../port/notification-sender.js";
import type { NotificationLog } from "../port/notification-log.js";
import type { Notification } from "../domain/notification.js";

// Corresponds to: operation ProcessPendingSchedules : application
//   needs ScheduleStore, NotificationSender, NotificationLog
export class ProcessPendingSchedules {
  constructor(
    private scheduleStore: ScheduleStore,
    private sender: NotificationSender,
    private log: NotificationLog,
  ) {}

  async execute(): Promise<{ processed: number; failed: number }> {
    const pending = await this.scheduleStore.findPending();
    let processed = 0;
    let failed = 0;

    for (const schedule of pending) {
      try {
        const notification: Notification = {
          id: crypto.randomUUID(),
          recipient: {
            id: schedule.recipientId,
            name: schedule.recipientId,
            email: null,
            phone: null,
            channel: "Email",
          },
          template: {
            id: schedule.templateId,
            name: schedule.templateId,
            subject: "",
            body: "",
            channel: "Email",
            vars: [],
          },
          channel: "Email",
          priority: schedule.priority,
          vars: schedule.vars,
          sentAt: null,
          status: "pending",
        };

        await this.sender.send(notification);
        notification.sentAt = new Date();
        notification.status = "sent";
        await this.log.record(notification);
        await this.scheduleStore.markExecuted(schedule.id);
        processed++;
      } catch {
        failed++;
      }
    }

    return { processed, failed };
  }
}

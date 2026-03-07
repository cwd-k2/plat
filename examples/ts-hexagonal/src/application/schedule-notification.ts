import type { Priority } from "../domain/notification.js";
import type { Schedule } from "../domain/schedule.js";
import type { ScheduleStore } from "../port/schedule-store.js";
import type { TemplateStore } from "../port/template-store.js";

// Corresponds to: operation ScheduleNotification : application
//   needs ScheduleStore, TemplateStore
export class ScheduleNotification {
  constructor(
    private scheduleStore: ScheduleStore,
    private templateStore: TemplateStore,
  ) {}

  async execute(input: {
    recipientId: string;
    templateId: string;
    vars: Map<string, string>;
    priority: Priority;
    scheduledAt: Date;
  }): Promise<string> {
    // Validate that the template exists.
    await this.templateStore.find(input.templateId);

    const schedule: Schedule = {
      id: crypto.randomUUID(),
      recipientId: input.recipientId,
      templateId: input.templateId,
      vars: input.vars,
      priority: input.priority,
      scheduledAt: input.scheduledAt,
      executedAt: null,
      status: "Pending",
    };

    await this.scheduleStore.save(schedule);
    return schedule.id;
  }
}

import type { ScheduleStore } from "../port/schedule-store.js";

// Corresponds to: operation CancelSchedule : application
//   needs ScheduleStore
export class CancelSchedule {
  constructor(private scheduleStore: ScheduleStore) {}

  async execute(scheduleId: string): Promise<void> {
    await this.scheduleStore.cancel(scheduleId);
  }
}

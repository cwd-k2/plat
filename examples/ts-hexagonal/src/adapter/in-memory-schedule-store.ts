import type { Schedule } from "../domain/schedule.js";
import type { ScheduleStore } from "../port/schedule-store.js";

// Corresponds to: adapter InMemoryScheduleStore : adapter implements ScheduleStore
// In-memory stub for concept verification.
export class InMemoryScheduleStore implements ScheduleStore {
  private store = new Map<string, Schedule>();

  async save(schedule: Schedule): Promise<void> {
    this.store.set(schedule.id, schedule);
  }

  async findPending(): Promise<Schedule[]> {
    const now = new Date();
    return [...this.store.values()].filter(
      (s) => s.status === "Pending" && s.scheduledAt <= now,
    );
  }

  async markExecuted(id: string): Promise<void> {
    const s = this.store.get(id);
    if (!s) throw new Error(`Schedule ${id} not found`);
    s.status = "Executed";
    s.executedAt = new Date();
  }

  async cancel(id: string): Promise<void> {
    const s = this.store.get(id);
    if (!s) throw new Error(`Schedule ${id} not found`);
    if (s.status !== "Pending") throw new Error(`Schedule ${id} is not pending`);
    s.status = "Cancelled";
  }
}

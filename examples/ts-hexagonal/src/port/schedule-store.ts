import type { Schedule } from "../domain/schedule.js";

// Corresponds to: boundary ScheduleStore : port
//   op save:         Schedule -> Error
//   op findPending:  () -> (List<Schedule>, Error)
//   op markExecuted: String -> Error
//   op cancel:       String -> Error
export interface ScheduleStore {
  save(schedule: Schedule): Promise<void>;
  findPending(): Promise<Schedule[]>;
  markExecuted(id: string): Promise<void>;
  cancel(id: string): Promise<void>;
}

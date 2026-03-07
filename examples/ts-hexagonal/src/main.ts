// Notification Service — TypeScript Hexagonal Architecture example.
//
// Wiring corresponds to:
//   compose EmailNotificationWiring
//     bind NotificationSender -> NodemailerSender (here: ConsoleSender)
//     bind TemplateStore      -> MongoTemplateStore (here: InMemoryTemplateStore)
//     bind NotificationLog    -> MongoNotificationLog (here: InMemoryNotificationLog)
//     bind ScheduleStore      -> InMemoryScheduleStore
//     bind PreferenceStore    -> InMemoryPreferenceStore
//     bind DeliveryTracker    -> ConsoleDeliveryTracker

import type { Template } from "./domain/notification.js";
import { InMemoryTemplateStore } from "./adapter/in-memory-template-store.js";
import { ConsoleSender } from "./adapter/console-sender.js";
import { InMemoryNotificationLog } from "./adapter/in-memory-notification-log.js";
import { InMemoryScheduleStore } from "./adapter/in-memory-schedule-store.js";
import { InMemoryPreferenceStore } from "./adapter/in-memory-preference-store.js";
import { ConsoleDeliveryTracker } from "./adapter/console-delivery-tracker.js";
import { SendNotification } from "./application/send-notification.js";
import { SendBulkNotification } from "./application/send-bulk-notification.js";
import { GetNotificationHistory } from "./application/get-notification-history.js";
import { ScheduleNotification } from "./application/schedule-notification.js";
import { ProcessPendingSchedules } from "./application/process-pending-schedules.js";
import { CancelSchedule } from "./application/cancel-schedule.js";
import { GetPreferences } from "./application/get-preferences.js";
import { UpdatePreferences } from "./application/update-preferences.js";
import { GetDeliveryReport } from "./application/get-delivery-report.js";

// --- Adapters ---
const templateStore = new InMemoryTemplateStore();
const emailSender = new ConsoleSender("email");
const notificationLog = new InMemoryNotificationLog();
const scheduleStore = new InMemoryScheduleStore();
const preferenceStore = new InMemoryPreferenceStore();
const deliveryTracker = new ConsoleDeliveryTracker();

// --- Seed data ---
const welcomeTemplate: Template = {
  id: "tpl-welcome",
  name: "Welcome",
  subject: "Welcome, {{name}}!",
  body: "Hello {{name}}, your account is ready.",
  channel: "Email",
  vars: ["name"],
};

const alertTemplate: Template = {
  id: "tpl-alert",
  name: "Alert",
  subject: "Alert: {{event}}",
  body: "Event {{event}} occurred at {{time}}.",
  channel: "Email",
  vars: ["event", "time"],
};

templateStore.seed(welcomeTemplate, alertTemplate);

// --- Use cases ---
const sendNotification = new SendNotification(templateStore, emailSender, notificationLog);
const sendBulk = new SendBulkNotification(templateStore, emailSender, notificationLog);
const getHistory = new GetNotificationHistory(notificationLog);
const scheduleNotification = new ScheduleNotification(scheduleStore, templateStore);
const processPending = new ProcessPendingSchedules(scheduleStore, emailSender, notificationLog);
const cancelSchedule = new CancelSchedule(scheduleStore);
const getPreferences = new GetPreferences(preferenceStore);
const updatePreferences = new UpdatePreferences(preferenceStore);
const getDeliveryReport = new GetDeliveryReport(deliveryTracker);

// --- Concept Verification ---
async function main() {
  console.log("=== TypeScript Hexagonal: Notification Service ===\n");

  // Single notification
  const id = await sendNotification.execute({
    recipientId: "user-001",
    templateId: "tpl-welcome",
    vars: new Map([["name", "Alice"]]),
    priority: "Normal",
  });
  console.log(`SendNotification: ${id}\n`);

  // Bulk notification
  const { sent, failed } = await sendBulk.execute({
    recipientIds: ["user-002", "user-003", "user-004"],
    templateId: "tpl-alert",
    vars: new Map([
      ["event", "deployment"],
      ["time", new Date().toISOString()],
    ]),
  });
  console.log(`\nSendBulk: ${sent} sent, ${failed} failed\n`);

  // History
  const history = await getHistory.execute("user-001");
  console.log(`GetHistory for user-001: ${history.length} notification(s)`);
  for (const n of history) {
    console.log(`  - ${n.id} [${n.channel}] status=${n.status} sentAt=${n.sentAt?.toISOString()}`);
  }

  // --- Scheduling ---
  console.log("\n--- Scheduling ---\n");

  const scheduleId = await scheduleNotification.execute({
    recipientId: "user-005",
    templateId: "tpl-welcome",
    vars: new Map([["name", "Bob"]]),
    priority: "High",
    scheduledAt: new Date(), // schedule for now
  });
  console.log(`ScheduleNotification: ${scheduleId}`);

  const { processed, failed: schedFailed } = await processPending.execute();
  console.log(`ProcessPendingSchedules: ${processed} processed, ${schedFailed} failed`);

  // Schedule and cancel
  const cancelId = await scheduleNotification.execute({
    recipientId: "user-006",
    templateId: "tpl-alert",
    vars: new Map([["event", "test"], ["time", "now"]]),
    priority: "Low",
    scheduledAt: new Date(Date.now() + 3600_000), // 1 hour from now
  });
  await cancelSchedule.execute(cancelId);
  console.log(`CancelSchedule: ${cancelId} cancelled`);

  // --- User Preferences ---
  console.log("\n--- User Preferences ---\n");

  await updatePreferences.execute({
    userId: "user-001",
    preferredChannel: "Email",
    enabled: true,
    quietStart: "22:00",
    quietEnd: "08:00",
  });
  const pref = await getPreferences.execute("user-001");
  console.log(`GetPreferences for user-001: channel=${pref.preferredChannel} enabled=${pref.enabled} quiet=${pref.quietStart}-${pref.quietEnd}`);

  // --- Delivery Tracking ---
  console.log("\n--- Delivery Tracking ---\n");

  const trackedNotification = {
    id: id,
    recipient: { id: "user-001", name: "user-001", email: null, phone: null, channel: "Email" as const },
    template: welcomeTemplate,
    channel: "Email" as const,
    priority: "Normal" as const,
    vars: new Map([["name", "Alice"]]),
    sentAt: new Date(),
    status: "sent",
  };
  await deliveryTracker.track(trackedNotification, "Email", "Delivered");
  const report = await getDeliveryReport.execute(id);
  console.log(`GetDeliveryReport for ${id}: status=${report.status} deliveredAt=${report.deliveredAt?.toISOString()}`);
}

main().catch(console.error);

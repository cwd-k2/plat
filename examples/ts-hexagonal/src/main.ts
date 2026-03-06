// Notification Service — TypeScript Hexagonal Architecture example.
//
// Wiring corresponds to:
//   compose EmailNotificationWiring
//     bind NotificationSender -> NodemailerSender (here: ConsoleSender)
//     bind TemplateStore      -> MongoTemplateStore (here: InMemoryTemplateStore)
//     bind NotificationLog    -> MongoNotificationLog (here: InMemoryNotificationLog)

import type { Template } from "./domain/notification.js";
import { InMemoryTemplateStore } from "./adapter/in-memory-template-store.js";
import { ConsoleSender } from "./adapter/console-sender.js";
import { InMemoryNotificationLog } from "./adapter/in-memory-notification-log.js";
import { SendNotification } from "./application/send-notification.js";
import { SendBulkNotification } from "./application/send-bulk-notification.js";
import { GetNotificationHistory } from "./application/get-notification-history.js";

// --- Adapters ---
const templateStore = new InMemoryTemplateStore();
const emailSender = new ConsoleSender("email");
const notificationLog = new InMemoryNotificationLog();

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
}

main().catch(console.error);

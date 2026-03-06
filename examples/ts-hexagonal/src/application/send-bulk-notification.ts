import type { Priority } from "../domain/notification.js";
import type { TemplateStore } from "../port/template-store.js";
import type { NotificationSender } from "../port/notification-sender.js";
import type { NotificationLog } from "../port/notification-log.js";
import { SendNotification } from "./send-notification.js";

// Corresponds to: operation SendBulkNotification : application
//   needs TemplateStore, NotificationSender, NotificationLog
export class SendBulkNotification {
  private single: SendNotification;

  constructor(
    templateStore: TemplateStore,
    sender: NotificationSender,
    log: NotificationLog,
  ) {
    this.single = new SendNotification(templateStore, sender, log);
  }

  async execute(input: {
    recipientIds: string[];
    templateId: string;
    vars: Map<string, string>;
    priority?: Priority;
  }): Promise<{ sent: number; failed: number }> {
    let sent = 0;
    let failed = 0;

    for (const recipientId of input.recipientIds) {
      try {
        await this.single.execute({
          recipientId,
          templateId: input.templateId,
          vars: input.vars,
          priority: input.priority ?? "Normal",
        });
        sent++;
      } catch {
        failed++;
      }
    }

    return { sent, failed };
  }
}

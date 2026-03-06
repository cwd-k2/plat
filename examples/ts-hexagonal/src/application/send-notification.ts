import type { Priority, Notification } from "../domain/notification.js";
import { renderTemplate } from "../domain/notification.js";
import type { TemplateStore } from "../port/template-store.js";
import type { NotificationSender } from "../port/notification-sender.js";
import type { NotificationLog } from "../port/notification-log.js";

// Corresponds to: operation SendNotification : application
//   needs TemplateStore, NotificationSender, NotificationLog
export class SendNotification {
  constructor(
    private templateStore: TemplateStore,
    private sender: NotificationSender,
    private log: NotificationLog,
  ) {}

  async execute(input: {
    recipientId: string;
    templateId: string;
    vars: Map<string, string>;
    priority: Priority;
  }): Promise<string> {
    const template = await this.templateStore.find(input.templateId);
    const { subject, body } = renderTemplate(template, input.vars);

    const notification: Notification = {
      id: crypto.randomUUID(),
      recipient: {
        id: input.recipientId,
        name: input.recipientId,
        email: null,
        phone: null,
        channel: template.channel,
      },
      template,
      channel: template.channel,
      priority: input.priority,
      vars: input.vars,
      sentAt: null,
      status: "pending",
    };

    await this.sender.send(notification);
    notification.sentAt = new Date();
    notification.status = "sent";
    await this.log.record(notification);

    return notification.id;
  }
}

import type { Notification } from "../domain/notification.js";
import { renderTemplate } from "../domain/notification.js";
import type { NotificationSender } from "../port/notification-sender.js";

// Corresponds to: adapter NodemailerSender / TwilioSender
// Console stub for concept verification — prints to stdout.
export class ConsoleSender implements NotificationSender {
  private label: string;

  constructor(label: string = "console") {
    this.label = label;
  }

  async send(notification: Notification): Promise<void> {
    const { subject, body } = renderTemplate(notification.template, notification.vars);
    console.log(
      `[${this.label}] → ${notification.channel} to ${notification.recipient.id}: "${subject}" — ${body}`,
    );
  }
}

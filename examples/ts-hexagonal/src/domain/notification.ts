// Domain models corresponding to plat-hs architecture definition.

export type Channel = "Email" | "SMS" | "Push" | "Slack";

export type Priority = "Low" | "Normal" | "High" | "Critical";

export interface Recipient {
  id: string;
  name: string;
  email: string | null;
  phone: string | null;
  channel: Channel;
}

export interface Template {
  id: string;
  name: string;
  subject: string;
  body: string;
  channel: Channel;
  vars: string[];
}

export interface Notification {
  id: string;
  recipient: Recipient;
  template: Template;
  channel: Channel;
  priority: Priority;
  vars: Map<string, string>;
  sentAt: Date | null;
  status: string;
}

// Template variable interpolation.
export function renderTemplate(
  template: Template,
  vars: Map<string, string>
): { subject: string; body: string } {
  let subject = template.subject;
  let body = template.body;
  for (const [key, value] of vars) {
    const placeholder = `{{${key}}}`;
    subject = subject.replaceAll(placeholder, value);
    body = body.replaceAll(placeholder, value);
  }
  return { subject, body };
}

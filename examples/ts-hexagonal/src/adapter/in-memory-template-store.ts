import type { Template } from "../domain/notification.js";
import type { TemplateStore } from "../port/template-store.js";

// Corresponds to: adapter MongoTemplateStore : adapter implements TemplateStore
// In-memory stub for concept verification.
export class InMemoryTemplateStore implements TemplateStore {
  private templates = new Map<string, Template>();

  seed(...templates: Template[]): void {
    for (const t of templates) {
      this.templates.set(t.id, t);
    }
  }

  async find(id: string): Promise<Template> {
    const t = this.templates.get(id);
    if (!t) throw new Error(`Template ${id} not found`);
    return t;
  }

  async findAll(): Promise<Template[]> {
    return [...this.templates.values()];
  }
}

import type { Template } from "../domain/notification.js";

// Corresponds to: boundary TemplateStore : port
//   op find:    String -> (Template, Error)
//   op findAll: () -> (List<Template>, Error)
export interface TemplateStore {
  find(id: string): Promise<Template>;
  findAll(): Promise<Template[]>;
}

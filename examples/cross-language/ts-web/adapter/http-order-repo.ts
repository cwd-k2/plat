import { Order } from "../domain/order";
import { OrderRepository } from "../port/repository";

export class HttpOrderRepo implements OrderRepository {
  constructor(private readonly baseUrl: string) {}

  async save(order: Order): Promise<void> {
    await fetch(`${this.baseUrl}/orders`, {
      method: "POST",
      body: JSON.stringify(order),
    });
  }

  async findById(id: string): Promise<Order> {
    const res = await fetch(`${this.baseUrl}/orders/${id}`);
    return res.json();
  }
}

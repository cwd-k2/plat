import { OrderRepository } from "../port/repository";

export class PlaceOrder {
  constructor(private readonly repo: OrderRepository) {}

  async execute(customerId: string, total: number): Promise<string> {
    // Creates and saves an order, returns order ID
    return "";
  }
}

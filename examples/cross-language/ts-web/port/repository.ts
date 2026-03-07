import { Order } from "../domain/order";

export interface OrderRepository {
  save(order: Order): Promise<void>;
  findById(id: string): Promise<Order>;
}

import { Order } from '../domain/order';

export interface OrderRepository {
    save(order: Order): void;
    findById(id: string): Order;
}

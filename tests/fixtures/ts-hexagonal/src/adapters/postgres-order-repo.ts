import { Order } from '../domain/order';
import { OrderRepository } from '../ports/order-repository';

export class PostgresOrderRepo implements OrderRepository {
    db: any;

    save(order: Order): void {
        // implementation
    }

    findById(id: string): Order {
        return new Order();
    }
}

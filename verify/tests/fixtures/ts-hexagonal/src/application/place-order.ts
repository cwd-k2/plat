import { OrderRepository } from '../ports/order-repository';

export class PlaceOrder {
    orderRepository: OrderRepository;

    constructor(orderRepository: OrderRepository) {
        this.orderRepository = orderRepository;
    }
}

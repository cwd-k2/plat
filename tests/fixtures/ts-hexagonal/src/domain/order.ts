export class OrderStatus {
    value: string;
}

export class Order {
    id: string;
    customerId: string;
    total: number;
    status: OrderStatus;
}

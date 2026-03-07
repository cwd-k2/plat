export enum OrderStatus {
  Draft = "draft",
  Placed = "placed",
}

export interface Order {
  id: string;
  customerId: string;
  total: number;
  status: OrderStatus;
}

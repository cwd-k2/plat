pub struct OrderStatus {
    pub value: String,
}

pub struct Order {
    pub id: String,
    pub customer_id: String,
    pub total: f64,
    pub status: OrderStatus,
}

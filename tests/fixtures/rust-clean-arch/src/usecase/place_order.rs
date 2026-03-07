use crate::port::order_repository::OrderRepository;

pub struct PlaceOrder {
    pub order_repository: Box<dyn OrderRepository>,
}

impl PlaceOrder {
    pub fn new(order_repository: Box<dyn OrderRepository>) -> Self {
        Self { order_repository }
    }
}

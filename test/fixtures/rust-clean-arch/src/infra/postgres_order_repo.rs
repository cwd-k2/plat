use crate::domain::order::Order;
use crate::port::order_repository::OrderRepository;

pub struct PostgresOrderRepo {
    pub db: PgPool,
}

impl PostgresOrderRepo {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }
}

impl OrderRepository for PostgresOrderRepo {
    fn save(&self, order: Order) -> Result<(), String> {
        Ok(())
    }

    fn find_by_id(&self, id: String) -> Result<Order, String> {
        todo!()
    }
}

use crate::domain::order::Order;

pub trait OrderRepository {
    fn save(&self, order: Order) -> Result<(), String>;
    fn find_by_id(&self, id: String) -> Result<Order, String>;
}

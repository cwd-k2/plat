package port

import (
	orderdomain "github.com/example/ecommerce/internal/order/domain"
)

// OrderRepository defines persistence operations for Order.
// Corresponds to: boundary OrderRepository : interface
type OrderRepository interface {
	Save(order *orderdomain.Order) error
	FindByID(id string) (*orderdomain.Order, error)
	FindAll() ([]*orderdomain.Order, error)
	Delete(id string) error
}

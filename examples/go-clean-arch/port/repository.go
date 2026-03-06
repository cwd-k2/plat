package port

import "github.com/example/order-service/domain"

// OrderRepository defines persistence operations for Order.
// Corresponds to: boundary OrderRepository : interface
type OrderRepository interface {
	Save(order *domain.Order) error
	FindByID(id string) (*domain.Order, error)
	FindAll() ([]*domain.Order, error)
	Delete(id string) error
}

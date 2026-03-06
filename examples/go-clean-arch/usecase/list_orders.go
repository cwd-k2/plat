package usecase

import (
	"github.com/example/order-service/domain"
	"github.com/example/order-service/port"
)

// ListOrders implements the ListOrders use case.
// Corresponds to: operation ListOrders : application
//   needs OrderRepository
type ListOrders struct {
	repo port.OrderRepository
}

func NewListOrders(repo port.OrderRepository) *ListOrders {
	return &ListOrders{repo: repo}
}

func (uc *ListOrders) Execute() ([]*domain.Order, error) {
	return uc.repo.FindAll()
}

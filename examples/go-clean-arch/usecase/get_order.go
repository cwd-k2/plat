package usecase

import (
	"github.com/example/order-service/domain"
	"github.com/example/order-service/port"
)

// GetOrder implements the GetOrder use case.
// Corresponds to: operation GetOrder : application
//   needs OrderRepository
type GetOrder struct {
	repo port.OrderRepository
}

func NewGetOrder(repo port.OrderRepository) *GetOrder {
	return &GetOrder{repo: repo}
}

func (uc *GetOrder) Execute(orderID string) (*domain.Order, error) {
	return uc.repo.FindByID(orderID)
}

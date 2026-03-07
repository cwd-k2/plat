package usecase

import (
	orderdomain "github.com/example/ecommerce/order/domain"
	orderport "github.com/example/ecommerce/order/port"
)

// GetOrder implements the GetOrder use case.
// Corresponds to: operation GetOrder : application
//
//	needs OrderRepository
type GetOrder struct {
	repo orderport.OrderRepository
}

func NewGetOrder(repo orderport.OrderRepository) *GetOrder {
	return &GetOrder{repo: repo}
}

func (uc *GetOrder) Execute(orderID string) (*orderdomain.Order, error) {
	return uc.repo.FindByID(orderID)
}

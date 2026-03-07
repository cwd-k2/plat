package usecase

import (
	orderdomain "github.com/example/ecommerce/internal/features/order/domain"
	orderport "github.com/example/ecommerce/internal/features/order/port"
)

// ListOrders implements the ListOrders use case.
// Corresponds to: operation ListOrders : application
//
//	needs OrderRepository
type ListOrders struct {
	repo orderport.OrderRepository
}

func NewListOrders(repo orderport.OrderRepository) *ListOrders {
	return &ListOrders{repo: repo}
}

func (uc *ListOrders) Execute() ([]*orderdomain.Order, error) {
	return uc.repo.FindAll()
}

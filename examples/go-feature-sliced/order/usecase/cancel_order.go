package usecase

import (
	"fmt"

	orderport "github.com/example/ecommerce/order/port"
)

// CancelOrder implements the CancelOrder use case.
// Corresponds to: operation CancelOrder : application
//
//	needs OrderRepository
type CancelOrder struct {
	repo orderport.OrderRepository
}

func NewCancelOrder(repo orderport.OrderRepository) *CancelOrder {
	return &CancelOrder{repo: repo}
}

func (uc *CancelOrder) Execute(orderID string) error {
	order, err := uc.repo.FindByID(orderID)
	if err != nil {
		return fmt.Errorf("order not found: %w", err)
	}

	if err := order.Cancel(); err != nil {
		return fmt.Errorf("cannot cancel: %w", err)
	}

	if err := uc.repo.Save(order); err != nil {
		return fmt.Errorf("save failed: %w", err)
	}

	return nil
}

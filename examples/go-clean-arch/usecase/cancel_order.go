package usecase

import (
	"fmt"

	"github.com/example/order-service/port"
)

// CancelOrder implements the CancelOrder use case.
// Corresponds to: operation CancelOrder : application
//   needs OrderRepository, PaymentGateway
type CancelOrder struct {
	repo    port.OrderRepository
	payment port.PaymentGateway
}

func NewCancelOrder(repo port.OrderRepository, payment port.PaymentGateway) *CancelOrder {
	return &CancelOrder{repo: repo, payment: payment}
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

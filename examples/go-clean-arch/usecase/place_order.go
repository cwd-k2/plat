package usecase

import (
	"fmt"

	"github.com/example/order-service/domain"
	"github.com/example/order-service/port"
)

// PlaceOrder implements the PlaceOrder use case.
// Corresponds to: operation PlaceOrder : application
//   needs OrderRepository, PaymentGateway, OrderNotifier
type PlaceOrder struct {
	repo     port.OrderRepository
	payment  port.PaymentGateway
	notifier port.OrderNotifier
}

func NewPlaceOrder(repo port.OrderRepository, payment port.PaymentGateway, notifier port.OrderNotifier) *PlaceOrder {
	return &PlaceOrder{repo: repo, payment: payment, notifier: notifier}
}

type PlaceOrderInput struct {
	Order        *domain.Order
	PaymentToken string
}

func (uc *PlaceOrder) Execute(in PlaceOrderInput) (string, error) {
	in.Order.RecalculateTotal()
	if err := in.Order.Validate(); err != nil {
		return "", fmt.Errorf("invalid order: %w", err)
	}

	txID, err := uc.payment.Charge(in.Order.Total, in.PaymentToken)
	if err != nil {
		return "", fmt.Errorf("payment failed: %w", err)
	}
	_ = txID

	in.Order.Confirm()
	if err := uc.repo.Save(in.Order); err != nil {
		return "", fmt.Errorf("save failed: %w", err)
	}

	_ = uc.notifier.OrderConfirmed(in.Order)

	return in.Order.ID, nil
}

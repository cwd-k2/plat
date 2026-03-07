package usecase

import (
	"fmt"

	orderdomain "github.com/example/ecommerce/internal/order/domain"
	orderport "github.com/example/ecommerce/internal/order/port"
	paymentport "github.com/example/ecommerce/internal/payment/port"
)

// PlaceOrder implements the PlaceOrder use case.
// Corresponds to: operation PlaceOrder : application
//
//	needs OrderRepository, PaymentGateway
type PlaceOrder struct {
	repo    orderport.OrderRepository
	payment paymentport.PaymentGateway
}

func NewPlaceOrder(repo orderport.OrderRepository, payment paymentport.PaymentGateway) *PlaceOrder {
	return &PlaceOrder{repo: repo, payment: payment}
}

type PlaceOrderInput struct {
	Order        *orderdomain.Order
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

	return in.Order.ID, nil
}

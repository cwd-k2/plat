package stripe

import (
	"fmt"

	"github.com/example/order-service/domain"
)

// Payment implements port.PaymentGateway.
// Corresponds to: adapter StripePayment : framework implements PaymentGateway
//   inject client: *stripe.Client
//
// Stub implementation for concept verification.
type Payment struct {
	nextTxID int
}

func NewPayment() *Payment {
	return &Payment{nextTxID: 1}
}

func (p *Payment) Charge(amount domain.Money, token string) (string, error) {
	if token == "" {
		return "", fmt.Errorf("payment token required")
	}
	if amount.Amount <= 0 {
		return "", fmt.Errorf("charge amount must be positive")
	}
	txID := fmt.Sprintf("tx_%d", p.nextTxID)
	p.nextTxID++
	return txID, nil
}

func (p *Payment) Refund(txID string) error {
	if txID == "" {
		return fmt.Errorf("transaction ID required")
	}
	return nil
}

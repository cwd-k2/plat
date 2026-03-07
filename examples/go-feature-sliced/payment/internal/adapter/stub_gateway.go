package adapter

import (
	"fmt"

	shareddomain "github.com/example/ecommerce/shared/domain"
)

// StubPaymentGateway implements payment/port.PaymentGateway.
// Corresponds to: adapter StubPaymentGateway : framework implements PaymentGateway
//
//	inject logger: log.Logger
//
// Stub implementation for concept verification.
type StubPaymentGateway struct {
	nextTxID int
}

func NewStubPaymentGateway() *StubPaymentGateway {
	return &StubPaymentGateway{nextTxID: 1}
}

func (g *StubPaymentGateway) Charge(amount shareddomain.Money, token string) (string, error) {
	if token == "" {
		return "", fmt.Errorf("payment token required")
	}
	if amount.Amount <= 0 {
		return "", fmt.Errorf("charge amount must be positive")
	}
	txID := fmt.Sprintf("tx_%d", g.nextTxID)
	g.nextTxID++
	return txID, nil
}

func (g *StubPaymentGateway) Refund(txID string) error {
	if txID == "" {
		return fmt.Errorf("transaction ID required")
	}
	return nil
}

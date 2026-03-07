package port

import (
	shareddomain "github.com/example/ecommerce/internal/shared/domain"
)

// PaymentGateway defines payment operations.
// Corresponds to: boundary PaymentGateway : interface
type PaymentGateway interface {
	Charge(amount shareddomain.Money, token string) (txID string, err error)
	Refund(txID string) error
}

package port

import "github.com/example/order-service/domain"

// PaymentGateway defines payment operations.
// Corresponds to: boundary PaymentGateway : interface
type PaymentGateway interface {
	Charge(amount domain.Money, token string) (txID string, err error)
	Refund(txID string) error
}

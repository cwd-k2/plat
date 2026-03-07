package port

import (
	paymentdomain "github.com/example/ecommerce/payment/domain"
)

// PaymentRepository defines persistence operations for Payment.
// Corresponds to: boundary PaymentRepository : interface
type PaymentRepository interface {
	Save(payment *paymentdomain.Payment) error
	FindByOrder(orderID string) (*paymentdomain.Payment, error)
}

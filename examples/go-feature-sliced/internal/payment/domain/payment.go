package domain

import (
	shareddomain "github.com/example/ecommerce/internal/shared/domain"
)

// PaymentStatus represents the lifecycle state of a payment.
// Corresponds to: model PaymentStatus : enterprise (enum)
type PaymentStatus string

const (
	PaymentPending   PaymentStatus = "Pending"
	PaymentCompleted PaymentStatus = "Completed"
	PaymentFailed    PaymentStatus = "Failed"
	PaymentRefunded  PaymentStatus = "Refunded"
)

// Payment represents a payment transaction.
// Corresponds to: model Payment : enterprise
type Payment struct {
	ID            string
	OrderID       string
	Amount        shareddomain.Money
	Status        PaymentStatus
	TransactionID string
}

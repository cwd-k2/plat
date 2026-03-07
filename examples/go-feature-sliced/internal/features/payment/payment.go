// Package payment provides the feature facade for Payment.
//
// Domain types and port interfaces live in sub-packages (domain/, port/).
// Use case and adapter implementations are accessed through factory functions.
package payment

import (
	"github.com/example/ecommerce/internal/features/payment/adapter"
	"github.com/example/ecommerce/internal/features/payment/usecase"
	"github.com/example/ecommerce/internal/features/payment/port"

	paymentdomain "github.com/example/ecommerce/internal/features/payment/domain"
)

// ProcessPaymentInput is the input for the ProcessPayment use case.
type ProcessPaymentInput = usecase.ProcessPaymentInput

// NewStubGateway creates a stub PaymentGateway for testing.
func NewStubGateway() port.PaymentGateway {
	return adapter.NewStubPaymentGateway()
}

// NewInMemoryRepo creates an in-memory PaymentRepository for testing.
func NewInMemoryRepo() port.PaymentRepository {
	return adapter.NewInMemoryPaymentRepo()
}

// NewProcessPayment creates a ProcessPayment use case wired with its dependencies.
func NewProcessPayment(gw port.PaymentGateway, repo port.PaymentRepository) interface {
	Execute(ProcessPaymentInput) (string, error)
} {
	return usecase.NewProcessPayment(gw, repo)
}

// NewGetPayment creates a GetPayment use case.
func NewGetPayment(repo port.PaymentRepository) interface {
	Execute(orderID string) (*paymentdomain.Payment, error)
} {
	return usecase.NewGetPayment(repo)
}

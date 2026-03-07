// Package payment provides the public API for the Payment feature.
//
// Domain types and port interfaces are re-exported from sub-packages.
// Use case and adapter implementations are encapsulated in internal/.
package payment

import (
	"github.com/example/ecommerce/payment/internal/adapter"
	"github.com/example/ecommerce/payment/internal/usecase"
	"github.com/example/ecommerce/payment/port"

	paymentdomain "github.com/example/ecommerce/payment/domain"
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

// Package order provides the feature facade for Order.
//
// Domain types and port interfaces live in sub-packages (domain/, port/).
// Use case and adapter implementations are accessed through factory functions.
package order

import (
	"github.com/example/ecommerce/internal/order/adapter"
	"github.com/example/ecommerce/internal/order/usecase"
	"github.com/example/ecommerce/internal/order/port"
	paymentport "github.com/example/ecommerce/internal/payment/port"

	orderdomain "github.com/example/ecommerce/internal/order/domain"
)

// PlaceOrderInput is the input for the PlaceOrder use case.
type PlaceOrderInput = usecase.PlaceOrderInput

// NewInMemoryRepo creates an in-memory OrderRepository for testing.
func NewInMemoryRepo() port.OrderRepository {
	return adapter.NewInMemoryOrderRepo()
}

// NewPlaceOrder creates a PlaceOrder use case wired with its dependencies.
func NewPlaceOrder(repo port.OrderRepository, pg paymentport.PaymentGateway) interface {
	Execute(PlaceOrderInput) (string, error)
} {
	return usecase.NewPlaceOrder(repo, pg)
}

// NewCancelOrder creates a CancelOrder use case.
func NewCancelOrder(repo port.OrderRepository) interface {
	Execute(orderID string) error
} {
	return usecase.NewCancelOrder(repo)
}

// NewGetOrder creates a GetOrder use case.
func NewGetOrder(repo port.OrderRepository) interface {
	Execute(orderID string) (*orderdomain.Order, error)
} {
	return usecase.NewGetOrder(repo)
}

// NewListOrders creates a ListOrders use case.
func NewListOrders(repo port.OrderRepository) interface {
	Execute() ([]*orderdomain.Order, error)
} {
	return usecase.NewListOrders(repo)
}

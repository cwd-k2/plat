// Package order provides the public API for the Order feature.
//
// Domain types and port interfaces are re-exported from sub-packages.
// Use case and adapter implementations are encapsulated in internal/.
package order

import (
	"github.com/example/ecommerce/order/internal/adapter"
	"github.com/example/ecommerce/order/internal/usecase"
	"github.com/example/ecommerce/order/port"
	paymentport "github.com/example/ecommerce/payment/port"

	orderdomain "github.com/example/ecommerce/order/domain"
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

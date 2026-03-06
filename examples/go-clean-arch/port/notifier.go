package port

import "github.com/example/order-service/domain"

// OrderNotifier sends notifications about order events.
// Corresponds to: boundary OrderNotifier : interface
type OrderNotifier interface {
	OrderConfirmed(order *domain.Order) error
}

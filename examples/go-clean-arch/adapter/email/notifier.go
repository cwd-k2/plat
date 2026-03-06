package email

import (
	"fmt"

	"github.com/example/order-service/domain"
)

// Notifier implements port.OrderNotifier.
// Corresponds to: adapter EmailNotifier : framework implements OrderNotifier
//   inject mailer: smtp.Sender
//
// Stub implementation for concept verification.
type Notifier struct{}

func NewNotifier() *Notifier {
	return &Notifier{}
}

func (n *Notifier) OrderConfirmed(order *domain.Order) error {
	fmt.Printf("[email] Order %s confirmed for %s (total: %.2f %s)\n",
		order.ID, order.Customer, order.Total.Amount, order.Total.Currency)
	return nil
}

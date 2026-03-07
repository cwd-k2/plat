package adapter

import (
	"fmt"
	"sync"

	paymentdomain "github.com/example/ecommerce/payment/domain"
)

// InMemoryPaymentRepo implements payment/port.PaymentRepository.
// Corresponds to: adapter InMemoryPaymentRepo : framework implements PaymentRepository
//
//	inject store: sync.Map
//
// This is an in-memory stub for concept verification.
type InMemoryPaymentRepo struct {
	mu       sync.RWMutex
	payments map[string]*paymentdomain.Payment
}

func NewInMemoryPaymentRepo() *InMemoryPaymentRepo {
	return &InMemoryPaymentRepo{payments: make(map[string]*paymentdomain.Payment)}
}

func (r *InMemoryPaymentRepo) Save(payment *paymentdomain.Payment) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.payments[payment.OrderID] = payment
	return nil
}

func (r *InMemoryPaymentRepo) FindByOrder(orderID string) (*paymentdomain.Payment, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	payment, ok := r.payments[orderID]
	if !ok {
		return nil, fmt.Errorf("payment for order %s not found", orderID)
	}
	return payment, nil
}

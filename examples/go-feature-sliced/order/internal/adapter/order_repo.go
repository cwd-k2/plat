package adapter

import (
	"fmt"
	"sync"

	orderdomain "github.com/example/ecommerce/order/domain"
)

// InMemoryOrderRepo implements order/port.OrderRepository.
// Corresponds to: adapter InMemoryOrderRepo : framework implements OrderRepository
//
//	inject store: sync.Map
//
// This is an in-memory stub for concept verification.
type InMemoryOrderRepo struct {
	mu     sync.RWMutex
	orders map[string]*orderdomain.Order
}

func NewInMemoryOrderRepo() *InMemoryOrderRepo {
	return &InMemoryOrderRepo{orders: make(map[string]*orderdomain.Order)}
}

func (r *InMemoryOrderRepo) Save(order *orderdomain.Order) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.orders[order.ID] = order
	return nil
}

func (r *InMemoryOrderRepo) FindByID(id string) (*orderdomain.Order, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	order, ok := r.orders[id]
	if !ok {
		return nil, fmt.Errorf("order %s not found", id)
	}
	return order, nil
}

func (r *InMemoryOrderRepo) FindAll() ([]*orderdomain.Order, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	result := make([]*orderdomain.Order, 0, len(r.orders))
	for _, o := range r.orders {
		result = append(result, o)
	}
	return result, nil
}

func (r *InMemoryOrderRepo) Delete(id string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if _, ok := r.orders[id]; !ok {
		return fmt.Errorf("order %s not found", id)
	}
	delete(r.orders, id)
	return nil
}

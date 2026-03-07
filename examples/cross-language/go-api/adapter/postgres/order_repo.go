package postgres

import (
	"fmt"
	"sync"

	"example/domain"
)

type OrderRepo struct {
	mu     sync.RWMutex
	orders map[string]*domain.Order
}

func NewOrderRepo() *OrderRepo {
	return &OrderRepo{orders: make(map[string]*domain.Order)}
}

func (r *OrderRepo) Save(order *domain.Order) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.orders[order.ID] = order
	return nil
}

func (r *OrderRepo) FindByID(id string) (*domain.Order, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	order, ok := r.orders[id]
	if !ok {
		return nil, fmt.Errorf("order %s not found", id)
	}
	return order, nil
}

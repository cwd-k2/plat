package postgres

import (
	"fmt"
	"sync"

	"github.com/example/order-service/domain"
)

// OrderRepo implements port.OrderRepository.
// Corresponds to: adapter PostgresOrderRepo : framework implements OrderRepository
//   inject db: *sql.DB
//
// This is an in-memory stub for concept verification.
// A real implementation would use *sql.DB.
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

func (r *OrderRepo) FindAll() ([]*domain.Order, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	result := make([]*domain.Order, 0, len(r.orders))
	for _, o := range r.orders {
		result = append(result, o)
	}
	return result, nil
}

func (r *OrderRepo) Delete(id string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if _, ok := r.orders[id]; !ok {
		return fmt.Errorf("order %s not found", id)
	}
	delete(r.orders, id)
	return nil
}

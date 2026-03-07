package postgres

import (
	"fmt"
	"sync"

	"github.com/example/order-service/domain"
)

// CustomerRepo implements port.CustomerRepository.
// Corresponds to: adapter PostgresCustomerRepo : framework implements CustomerRepository
//   inject db: *sql.DB
//
// This is an in-memory stub for concept verification.
// A real implementation would use *sql.DB.
type CustomerRepo struct {
	mu        sync.RWMutex
	customers map[string]*domain.Customer
	byEmail   map[string]string // email -> id
}

func NewCustomerRepo() *CustomerRepo {
	return &CustomerRepo{
		customers: make(map[string]*domain.Customer),
		byEmail:   make(map[string]string),
	}
}

func (r *CustomerRepo) Save(customer *domain.Customer) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.customers[customer.ID] = customer
	r.byEmail[customer.Email] = customer.ID
	return nil
}

func (r *CustomerRepo) FindByID(id string) (*domain.Customer, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	customer, ok := r.customers[id]
	if !ok {
		return nil, fmt.Errorf("customer %s not found", id)
	}
	return customer, nil
}

func (r *CustomerRepo) FindByEmail(email string) (*domain.Customer, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	id, ok := r.byEmail[email]
	if !ok {
		return nil, fmt.Errorf("customer with email %s not found", email)
	}
	return r.customers[id], nil
}

func (r *CustomerRepo) Delete(id string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	customer, ok := r.customers[id]
	if !ok {
		return fmt.Errorf("customer %s not found", id)
	}
	delete(r.byEmail, customer.Email)
	delete(r.customers, id)
	return nil
}

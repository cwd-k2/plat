package port

import "github.com/example/order-service/domain"

// CustomerRepository defines persistence operations for Customer.
// Corresponds to: boundary CustomerRepository : interface
type CustomerRepository interface {
	Save(customer *domain.Customer) error
	FindByID(id string) (*domain.Customer, error)
	FindByEmail(email string) (*domain.Customer, error)
	Delete(id string) error
}

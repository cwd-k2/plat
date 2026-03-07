package usecase

import (
	"fmt"

	"github.com/example/order-service/domain"
	"github.com/example/order-service/port"
)

// CreateCustomer implements the CreateCustomer use case.
// Corresponds to: operation CreateCustomer : application
//   needs CustomerRepository
type CreateCustomer struct {
	repo port.CustomerRepository
}

func NewCreateCustomer(repo port.CustomerRepository) *CreateCustomer {
	return &CreateCustomer{repo: repo}
}

func (uc *CreateCustomer) Execute(customer *domain.Customer) error {
	if err := customer.Validate(); err != nil {
		return fmt.Errorf("invalid customer: %w", err)
	}

	if err := uc.repo.Save(customer); err != nil {
		return fmt.Errorf("save failed: %w", err)
	}

	return nil
}

package usecase

import (
	"fmt"

	"github.com/example/order-service/domain"
	"github.com/example/order-service/port"
)

// UpdateCustomerAddress implements the UpdateCustomerAddress use case.
// Corresponds to: operation UpdateCustomerAddress : application
//   needs CustomerRepository
type UpdateCustomerAddress struct {
	repo port.CustomerRepository
}

func NewUpdateCustomerAddress(repo port.CustomerRepository) *UpdateCustomerAddress {
	return &UpdateCustomerAddress{repo: repo}
}

func (uc *UpdateCustomerAddress) Execute(customerID string, address domain.Address) error {
	customer, err := uc.repo.FindByID(customerID)
	if err != nil {
		return fmt.Errorf("customer not found: %w", err)
	}

	customer.Address = address

	if err := uc.repo.Save(customer); err != nil {
		return fmt.Errorf("save failed: %w", err)
	}

	return nil
}

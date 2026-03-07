package usecase

import (
	"github.com/example/order-service/domain"
	"github.com/example/order-service/port"
)

// GetCustomer implements the GetCustomer use case.
// Corresponds to: operation GetCustomer : application
//   needs CustomerRepository
type GetCustomer struct {
	repo port.CustomerRepository
}

func NewGetCustomer(repo port.CustomerRepository) *GetCustomer {
	return &GetCustomer{repo: repo}
}

func (uc *GetCustomer) Execute(customerID string) (*domain.Customer, error) {
	return uc.repo.FindByID(customerID)
}

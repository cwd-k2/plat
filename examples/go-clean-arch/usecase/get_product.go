package usecase

import (
	"github.com/example/order-service/domain"
	"github.com/example/order-service/port"
)

// GetProduct implements the GetProduct use case.
// Corresponds to: operation GetProduct : application
//   needs ProductRepository
type GetProduct struct {
	repo port.ProductRepository
}

func NewGetProduct(repo port.ProductRepository) *GetProduct {
	return &GetProduct{repo: repo}
}

func (uc *GetProduct) Execute(productID string) (*domain.Product, error) {
	return uc.repo.FindByID(productID)
}

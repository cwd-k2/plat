package usecase

import (
	catalogdomain "github.com/example/ecommerce/internal/features/catalog/domain"
	catalogport "github.com/example/ecommerce/internal/features/catalog/port"
)

// GetProduct implements the GetProduct use case.
// Corresponds to: operation GetProduct : application
//
//	needs ProductRepository
type GetProduct struct {
	repo catalogport.ProductRepository
}

func NewGetProduct(repo catalogport.ProductRepository) *GetProduct {
	return &GetProduct{repo: repo}
}

func (uc *GetProduct) Execute(productID string) (*catalogdomain.Product, error) {
	return uc.repo.FindByID(productID)
}

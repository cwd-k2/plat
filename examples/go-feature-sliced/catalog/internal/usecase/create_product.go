package usecase

import (
	"fmt"

	catalogdomain "github.com/example/ecommerce/catalog/domain"
	catalogport "github.com/example/ecommerce/catalog/port"
)

// CreateProduct implements the CreateProduct use case.
// Corresponds to: operation CreateProduct : application
//
//	needs ProductRepository
type CreateProduct struct {
	repo catalogport.ProductRepository
}

func NewCreateProduct(repo catalogport.ProductRepository) *CreateProduct {
	return &CreateProduct{repo: repo}
}

func (uc *CreateProduct) Execute(product *catalogdomain.Product) error {
	if err := product.Validate(); err != nil {
		return fmt.Errorf("invalid product: %w", err)
	}

	if err := uc.repo.Save(product); err != nil {
		return fmt.Errorf("save failed: %w", err)
	}

	return nil
}

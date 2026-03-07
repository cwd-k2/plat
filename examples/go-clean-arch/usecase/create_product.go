package usecase

import (
	"fmt"

	"github.com/example/order-service/domain"
	"github.com/example/order-service/port"
)

// CreateProduct implements the CreateProduct use case.
// Corresponds to: operation CreateProduct : application
//   needs ProductRepository
type CreateProduct struct {
	repo port.ProductRepository
}

func NewCreateProduct(repo port.ProductRepository) *CreateProduct {
	return &CreateProduct{repo: repo}
}

func (uc *CreateProduct) Execute(product *domain.Product) error {
	if err := product.Validate(); err != nil {
		return fmt.Errorf("invalid product: %w", err)
	}

	if err := uc.repo.Save(product); err != nil {
		return fmt.Errorf("save failed: %w", err)
	}

	return nil
}

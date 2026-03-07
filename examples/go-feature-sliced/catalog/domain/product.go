package domain

import (
	"fmt"

	shareddomain "github.com/example/ecommerce/shared/domain"
)

// Product represents a catalog product.
// Corresponds to: model Product : enterprise
type Product struct {
	ID          string
	Name        string
	Description string
	Price       shareddomain.Money
	CategoryID  string
	Stock       int
}

// Validate checks product invariants: price > 0, stock >= 0.
func (p *Product) Validate() error {
	if p.Price.Amount <= 0 {
		return fmt.Errorf("product price must be positive, got %f", p.Price.Amount)
	}
	if p.Stock < 0 {
		return fmt.Errorf("product stock must be non-negative, got %d", p.Stock)
	}
	return nil
}

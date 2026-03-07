package domain

import "fmt"

// Product represents a catalog product.
type Product struct {
	ID          string
	Name        string
	Description string
	Price       Money
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

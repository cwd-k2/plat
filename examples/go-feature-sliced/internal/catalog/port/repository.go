package port

import (
	catalogdomain "github.com/example/ecommerce/internal/catalog/domain"
)

// ProductRepository defines persistence operations for Product.
// Corresponds to: boundary ProductRepository : interface
type ProductRepository interface {
	Save(product *catalogdomain.Product) error
	FindByID(id string) (*catalogdomain.Product, error)
	FindAll() ([]*catalogdomain.Product, error)
	Delete(id string) error
}

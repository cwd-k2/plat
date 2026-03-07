package port

import "github.com/example/order-service/domain"

// ProductRepository defines persistence operations for Product.
// Corresponds to: boundary ProductRepository : interface
type ProductRepository interface {
	Save(product *domain.Product) error
	FindByID(id string) (*domain.Product, error)
	FindAll() ([]*domain.Product, error)
	Search(query string) ([]*domain.Product, error)
	Delete(id string) error
}

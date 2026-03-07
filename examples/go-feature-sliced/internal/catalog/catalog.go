// Package catalog provides the feature facade for Catalog.
//
// Domain types and port interfaces live in sub-packages (domain/, port/).
// Use case and adapter implementations are accessed through factory functions.
package catalog

import (
	"github.com/example/ecommerce/internal/catalog/adapter"
	"github.com/example/ecommerce/internal/catalog/usecase"
	"github.com/example/ecommerce/internal/catalog/port"

	catalogdomain "github.com/example/ecommerce/internal/catalog/domain"
)

// NewInMemoryProductRepo creates an in-memory ProductRepository and ProductSearch for testing.
func NewInMemoryProductRepo() interface {
	port.ProductRepository
	port.ProductSearch
} {
	return adapter.NewInMemoryProductRepo()
}

// NewCreateProduct creates a CreateProduct use case.
func NewCreateProduct(repo port.ProductRepository) interface {
	Execute(product *catalogdomain.Product) error
} {
	return usecase.NewCreateProduct(repo)
}

// NewGetProduct creates a GetProduct use case.
func NewGetProduct(repo port.ProductRepository) interface {
	Execute(productID string) (*catalogdomain.Product, error)
} {
	return usecase.NewGetProduct(repo)
}

// NewSearchProducts creates a SearchProducts use case.
func NewSearchProducts(search port.ProductSearch) interface {
	Execute(query string) ([]*catalogdomain.Product, error)
} {
	return usecase.NewSearchProducts(search)
}

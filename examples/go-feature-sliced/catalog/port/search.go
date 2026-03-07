package port

import (
	catalogdomain "github.com/example/ecommerce/catalog/domain"
)

// ProductSearch defines search operations for Product.
// Corresponds to: boundary ProductSearch : interface
type ProductSearch interface {
	Search(query string) ([]*catalogdomain.Product, error)
}

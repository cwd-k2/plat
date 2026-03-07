package usecase

import (
	catalogdomain "github.com/example/ecommerce/catalog/domain"
	catalogport "github.com/example/ecommerce/catalog/port"
)

// SearchProducts implements the SearchProducts use case.
// Corresponds to: operation SearchProducts : application
//
//	needs ProductSearch
type SearchProducts struct {
	search catalogport.ProductSearch
}

func NewSearchProducts(search catalogport.ProductSearch) *SearchProducts {
	return &SearchProducts{search: search}
}

func (uc *SearchProducts) Execute(query string) ([]*catalogdomain.Product, error) {
	return uc.search.Search(query)
}

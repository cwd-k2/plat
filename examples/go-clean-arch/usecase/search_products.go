package usecase

import (
	"github.com/example/order-service/domain"
	"github.com/example/order-service/port"
)

// SearchProducts implements the SearchProducts use case.
// Corresponds to: operation SearchProducts : application
//   needs ProductRepository
type SearchProducts struct {
	repo port.ProductRepository
}

func NewSearchProducts(repo port.ProductRepository) *SearchProducts {
	return &SearchProducts{repo: repo}
}

func (uc *SearchProducts) Execute(query string) ([]*domain.Product, error) {
	return uc.repo.Search(query)
}

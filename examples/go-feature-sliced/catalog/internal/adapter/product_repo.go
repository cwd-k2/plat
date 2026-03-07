package adapter

import (
	"fmt"
	"strings"
	"sync"

	catalogdomain "github.com/example/ecommerce/catalog/domain"
)

// InMemoryProductRepo implements catalog/port.ProductRepository and catalog/port.ProductSearch.
// Corresponds to: adapter InMemoryProductRepo : framework implements ProductRepository
// Corresponds to: adapter InMemoryProductSearch : framework implements ProductSearch
//
//	inject store: sync.Map
//
// This is an in-memory stub for concept verification.
type InMemoryProductRepo struct {
	mu       sync.RWMutex
	products map[string]*catalogdomain.Product
}

func NewInMemoryProductRepo() *InMemoryProductRepo {
	return &InMemoryProductRepo{products: make(map[string]*catalogdomain.Product)}
}

func (r *InMemoryProductRepo) Save(product *catalogdomain.Product) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.products[product.ID] = product
	return nil
}

func (r *InMemoryProductRepo) FindByID(id string) (*catalogdomain.Product, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	product, ok := r.products[id]
	if !ok {
		return nil, fmt.Errorf("product %s not found", id)
	}
	return product, nil
}

func (r *InMemoryProductRepo) FindAll() ([]*catalogdomain.Product, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	result := make([]*catalogdomain.Product, 0, len(r.products))
	for _, p := range r.products {
		result = append(result, p)
	}
	return result, nil
}

func (r *InMemoryProductRepo) Search(query string) ([]*catalogdomain.Product, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	var result []*catalogdomain.Product
	lower := strings.ToLower(query)
	for _, p := range r.products {
		if strings.Contains(strings.ToLower(p.Name), lower) ||
			strings.Contains(strings.ToLower(p.Description), lower) {
			result = append(result, p)
		}
	}
	return result, nil
}

func (r *InMemoryProductRepo) Delete(id string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if _, ok := r.products[id]; !ok {
		return fmt.Errorf("product %s not found", id)
	}
	delete(r.products, id)
	return nil
}

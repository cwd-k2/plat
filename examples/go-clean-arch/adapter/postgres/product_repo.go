package postgres

import (
	"fmt"
	"strings"
	"sync"

	"github.com/example/order-service/domain"
)

// ProductRepo implements port.ProductRepository.
// Corresponds to: adapter PostgresProductRepo : framework implements ProductRepository
//   inject db: *sql.DB
//
// This is an in-memory stub for concept verification.
// A real implementation would use *sql.DB.
type ProductRepo struct {
	mu       sync.RWMutex
	products map[string]*domain.Product
}

func NewProductRepo() *ProductRepo {
	return &ProductRepo{products: make(map[string]*domain.Product)}
}

func (r *ProductRepo) Save(product *domain.Product) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.products[product.ID] = product
	return nil
}

func (r *ProductRepo) FindByID(id string) (*domain.Product, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	product, ok := r.products[id]
	if !ok {
		return nil, fmt.Errorf("product %s not found", id)
	}
	return product, nil
}

func (r *ProductRepo) FindAll() ([]*domain.Product, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	result := make([]*domain.Product, 0, len(r.products))
	for _, p := range r.products {
		result = append(result, p)
	}
	return result, nil
}

func (r *ProductRepo) Search(query string) ([]*domain.Product, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	var result []*domain.Product
	lower := strings.ToLower(query)
	for _, p := range r.products {
		if strings.Contains(strings.ToLower(p.Name), lower) ||
			strings.Contains(strings.ToLower(p.Description), lower) {
			result = append(result, p)
		}
	}
	return result, nil
}

func (r *ProductRepo) Delete(id string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if _, ok := r.products[id]; !ok {
		return fmt.Errorf("product %s not found", id)
	}
	delete(r.products, id)
	return nil
}

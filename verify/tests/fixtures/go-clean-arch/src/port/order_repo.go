package port

import "example/domain"

type OrderRepository interface {
	Save(order domain.Order) error
	FindById(id string) (domain.Order, error)
}

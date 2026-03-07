package usecase

import "example/port"

type PlaceOrder struct {
	repo port.OrderRepository
}

func NewPlaceOrder(repo port.OrderRepository) *PlaceOrder {
	return &PlaceOrder{repo: repo}
}

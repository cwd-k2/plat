package domain

type OrderStatus string

const (
	OrderStatusDraft  OrderStatus = "draft"
	OrderStatusPlaced OrderStatus = "placed"
	OrderStatusPaid   OrderStatus = "paid"
)

type Order struct {
	Id         string
	CustomerId string
	Total      float64
	Status     OrderStatus
}

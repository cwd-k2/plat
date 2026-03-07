package domain

type OrderStatus string

const (
	OrderStatusDraft  OrderStatus = "draft"
	OrderStatusPlaced OrderStatus = "placed"
)

type Order struct {
	ID         string
	CustomerID string
	Total      float64
	Status     OrderStatus
}

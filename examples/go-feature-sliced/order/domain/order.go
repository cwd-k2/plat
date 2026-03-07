package domain

import (
	"fmt"

	shareddomain "github.com/example/ecommerce/shared/domain"
)

// OrderStatus represents the lifecycle state of an order.
// Corresponds to: model OrderStatus : enterprise (enum)
type OrderStatus string

const (
	StatusPending   OrderStatus = "Pending"
	StatusConfirmed OrderStatus = "Confirmed"
	StatusShipped   OrderStatus = "Shipped"
	StatusDelivered OrderStatus = "Delivered"
	StatusCancelled OrderStatus = "Cancelled"
)

// OrderItem is a value object within an Order.
// Corresponds to: model OrderItem : enterprise (value object)
type OrderItem struct {
	ProductID string
	Name      string
	Quantity  int
	Price     shareddomain.Money
}

func (item OrderItem) Subtotal() shareddomain.Money {
	return shareddomain.Money{
		Amount:   item.Price.Amount * float64(item.Quantity),
		Currency: item.Price.Currency,
	}
}

// Order is the aggregate root.
// Corresponds to: model Order : enterprise (aggregate)
//
//	invariant positiveTotal: total.amount > 0
type Order struct {
	ID         string
	CustomerID string
	Items      []OrderItem
	Total      shareddomain.Money
	Shipping   shareddomain.Address
	Status     OrderStatus
}

// Validate checks the positiveTotal invariant.
func (o *Order) Validate() error {
	if o.Total.Amount <= 0 {
		return fmt.Errorf("invariant violated: total must be positive, got %f", o.Total.Amount)
	}
	return nil
}

func (o *Order) Cancel() error {
	if o.Status == StatusCancelled {
		return fmt.Errorf("order already cancelled")
	}
	if o.Status == StatusDelivered {
		return fmt.Errorf("cannot cancel delivered order")
	}
	o.Status = StatusCancelled
	return nil
}

func (o *Order) Confirm() {
	o.Status = StatusConfirmed
}

// RecalculateTotal computes total from items.
func (o *Order) RecalculateTotal() {
	var total float64
	currency := "USD"
	for _, item := range o.Items {
		sub := item.Subtotal()
		total += sub.Amount
		currency = sub.Currency
	}
	o.Total = shareddomain.Money{Amount: total, Currency: currency}
}

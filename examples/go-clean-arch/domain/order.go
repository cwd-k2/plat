package domain

import "fmt"

// Order is the aggregate root.
type Order struct {
	ID       string
	Customer string
	Items    []OrderItem
	Total    Money
	Shipping Address
	Status   OrderStatus
}

// Invariant: positiveTotal — total.amount > 0
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
	o.Total = Money{Amount: total, Currency: currency}
}

package domain

// OrderItem is a value object within an Order.
type OrderItem struct {
	ProductID string
	Name      string
	Quantity  int
	Price     Money
}

func (item OrderItem) Subtotal() Money {
	return Money{
		Amount:   item.Price.Amount * float64(item.Quantity),
		Currency: item.Price.Currency,
	}
}

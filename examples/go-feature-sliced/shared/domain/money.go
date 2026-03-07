package domain

import "fmt"

// Money is a value object representing a monetary amount.
// Corresponds to: model Money : enterprise (value object)
type Money struct {
	Amount   float64
	Currency string
}

func NewMoney(amount float64, currency string) (Money, error) {
	if amount < 0 {
		return Money{}, fmt.Errorf("money amount must be non-negative: %f", amount)
	}
	if currency == "" {
		return Money{}, fmt.Errorf("currency must not be empty")
	}
	return Money{Amount: amount, Currency: currency}, nil
}

func (m Money) Add(other Money) (Money, error) {
	if m.Currency != other.Currency {
		return Money{}, fmt.Errorf("cannot add %s to %s", other.Currency, m.Currency)
	}
	return Money{Amount: m.Amount + other.Amount, Currency: m.Currency}, nil
}

func (m Money) IsZero() bool {
	return m.Amount == 0
}

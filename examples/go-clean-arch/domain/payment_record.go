package domain

// PaymentRecord represents a record of a payment transaction.
type PaymentRecord struct {
	ID            string
	OrderID       string
	Amount        Money
	Method        string
	Status        string
	TransactionID string
}

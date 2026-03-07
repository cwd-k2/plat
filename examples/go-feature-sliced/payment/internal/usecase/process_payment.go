package usecase

import (
	"fmt"

	shareddomain "github.com/example/ecommerce/shared/domain"

	paymentdomain "github.com/example/ecommerce/payment/domain"
	paymentport "github.com/example/ecommerce/payment/port"
)

// ProcessPayment implements the ProcessPayment use case.
// Corresponds to: operation ProcessPayment : application
//
//	needs PaymentGateway, PaymentRepository
type ProcessPayment struct {
	gateway paymentport.PaymentGateway
	repo    paymentport.PaymentRepository
}

func NewProcessPayment(gateway paymentport.PaymentGateway, repo paymentport.PaymentRepository) *ProcessPayment {
	return &ProcessPayment{gateway: gateway, repo: repo}
}

type ProcessPaymentInput struct {
	OrderID      string
	Amount       shareddomain.Money
	PaymentToken string
}

func (uc *ProcessPayment) Execute(in ProcessPaymentInput) (string, error) {
	txID, err := uc.gateway.Charge(in.Amount, in.PaymentToken)
	if err != nil {
		return "", fmt.Errorf("charge failed: %w", err)
	}

	p := &paymentdomain.Payment{
		ID:            fmt.Sprintf("pay-%s", in.OrderID),
		OrderID:       in.OrderID,
		Amount:        in.Amount,
		Status:        paymentdomain.PaymentCompleted,
		TransactionID: txID,
	}

	if err := uc.repo.Save(p); err != nil {
		return "", fmt.Errorf("save payment failed: %w", err)
	}

	return p.ID, nil
}

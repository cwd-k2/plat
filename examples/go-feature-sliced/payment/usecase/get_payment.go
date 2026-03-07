package usecase

import (
	paymentdomain "github.com/example/ecommerce/payment/domain"
	paymentport "github.com/example/ecommerce/payment/port"
)

// GetPayment implements the GetPayment use case.
// Corresponds to: operation GetPayment : application
//
//	needs PaymentRepository
type GetPayment struct {
	repo paymentport.PaymentRepository
}

func NewGetPayment(repo paymentport.PaymentRepository) *GetPayment {
	return &GetPayment{repo: repo}
}

func (uc *GetPayment) Execute(orderID string) (*paymentdomain.Payment, error) {
	return uc.repo.FindByOrder(orderID)
}

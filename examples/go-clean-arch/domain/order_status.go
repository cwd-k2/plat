package domain

type OrderStatus string

const (
	StatusPending   OrderStatus = "Pending"
	StatusConfirmed OrderStatus = "Confirmed"
	StatusShipped   OrderStatus = "Shipped"
	StatusDelivered OrderStatus = "Delivered"
	StatusCancelled OrderStatus = "Cancelled"
)

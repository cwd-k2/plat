package domain

import (
	"fmt"
	"time"
)

// CustomerStatus represents the lifecycle state of a customer.
type CustomerStatus string

const (
	CustomerActive    CustomerStatus = "Active"
	CustomerSuspended CustomerStatus = "Suspended"
	CustomerDeleted   CustomerStatus = "Deleted"
)

// Customer is the aggregate root for customer management.
type Customer struct {
	ID        string
	Name      string
	Email     string
	Phone     string
	Address   Address
	CreatedAt time.Time
	Status    CustomerStatus
}

// Validate checks customer invariants.
func (c *Customer) Validate() error {
	if c.Name == "" {
		return fmt.Errorf("customer name must not be empty")
	}
	if c.Email == "" {
		return fmt.Errorf("customer email must not be empty")
	}
	return nil
}

// Deactivate marks the customer as suspended.
func (c *Customer) Deactivate() error {
	if c.Status == CustomerDeleted {
		return fmt.Errorf("cannot deactivate deleted customer")
	}
	c.Status = CustomerSuspended
	return nil
}

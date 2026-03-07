package stub

// Inventory implements port.InventoryChecker.
// Corresponds to: adapter StubInventory : framework implements InventoryChecker
//   inject db: *sql.DB
//
// Stub implementation that always returns available for concept verification.
type Inventory struct{}

func NewInventory() *Inventory {
	return &Inventory{}
}

func (inv *Inventory) Check(productID string, quantity int) (bool, error) {
	// Stub: always available
	return true, nil
}

package port

// InventoryChecker checks product availability.
// Corresponds to: boundary InventoryChecker : interface
type InventoryChecker interface {
	Check(productID string, quantity int) (bool, error)
}

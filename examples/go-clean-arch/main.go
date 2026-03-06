// Order Service — Go Clean Architecture example.
//
// Wiring corresponds to: compose OrderServiceWiring
//   bind OrderRepository  -> PostgresOrderRepo
//   bind PaymentGateway   -> StripePayment
//   bind OrderNotifier    -> EmailNotifier
//   entry OrderController
package main

import (
	"fmt"
	"net/http"

	"github.com/example/order-service/adapter/email"
	httpctl "github.com/example/order-service/adapter/http"
	"github.com/example/order-service/adapter/postgres"
	"github.com/example/order-service/adapter/stripe"
	"github.com/example/order-service/domain"
	"github.com/example/order-service/usecase"
)

func main() {
	// --- Adapters (framework layer) ---
	repo := postgres.NewOrderRepo()
	payment := stripe.NewPayment()
	notifier := email.NewNotifier()

	// --- Use cases (application layer) ---
	placeOrder := usecase.NewPlaceOrder(repo, payment, notifier)
	cancelOrder := usecase.NewCancelOrder(repo, payment)
	getOrder := usecase.NewGetOrder(repo)
	listOrders := usecase.NewListOrders(repo)

	// --- Controller (framework layer) ---
	controller := httpctl.NewOrderController(placeOrder, listOrders, getOrder, cancelOrder)
	controller.Verify()

	// --- Concept verification: in-process use case execution ---
	fmt.Println("\n--- Concept Verification ---")

	order := &domain.Order{
		ID:       "ord-001",
		Customer: "Alice",
		Items: []domain.OrderItem{
			{ProductID: "prod-1", Name: "Widget", Quantity: 2, Price: domain.Money{Amount: 25.00, Currency: "USD"}},
			{ProductID: "prod-2", Name: "Gadget", Quantity: 1, Price: domain.Money{Amount: 50.00, Currency: "USD"}},
		},
		Shipping: domain.Address{Street: "123 Main St", City: "Springfield", Country: "US"},
		Status:   domain.StatusPending,
	}

	orderID, err := placeOrder.Execute(usecase.PlaceOrderInput{
		Order:        order,
		PaymentToken: "tok_test_123",
	})
	if err != nil {
		fmt.Printf("PlaceOrder failed: %v\n", err)
		return
	}
	fmt.Printf("PlaceOrder succeeded: %s\n", orderID)

	found, err := getOrder.Execute(orderID)
	if err != nil {
		fmt.Printf("GetOrder failed: %v\n", err)
		return
	}
	fmt.Printf("GetOrder: %s status=%s total=%.2f %s\n",
		found.ID, found.Status, found.Total.Amount, found.Total.Currency)

	all, _ := listOrders.Execute()
	fmt.Printf("ListOrders: %d order(s)\n", len(all))

	if err := cancelOrder.Execute(orderID); err != nil {
		fmt.Printf("CancelOrder failed: %v\n", err)
		return
	}
	fmt.Printf("CancelOrder succeeded: %s\n", orderID)

	found, _ = getOrder.Execute(orderID)
	fmt.Printf("GetOrder after cancel: status=%s\n", found.Status)

	// --- HTTP server (optional, uncomment to run) ---
	// mux := http.NewServeMux()
	// controller.RegisterRoutes(mux)
	// fmt.Println("\nListening on :8080")
	// http.ListenAndServe(":8080", mux)
	_ = http.NewServeMux // suppress unused import
}

// Order Service — Go Clean Architecture example.
//
// Wiring corresponds to: compose OrderServiceWiring
//   bind OrderRepository      -> PostgresOrderRepo
//   bind PaymentGateway       -> StripePayment
//   bind OrderNotifier        -> EmailNotifier
//   bind CustomerRepository   -> PostgresCustomerRepo
//   bind ProductRepository    -> PostgresProductRepo
//   bind InventoryChecker     -> StubInventory
//   entry OrderController
package main

import (
	"fmt"
	"net/http"
	"time"

	"github.com/example/order-service/adapter/email"
	httpctl "github.com/example/order-service/adapter/http"
	"github.com/example/order-service/adapter/postgres"
	"github.com/example/order-service/adapter/stripe"
	"github.com/example/order-service/adapter/stub"
	"github.com/example/order-service/domain"
	"github.com/example/order-service/usecase"
)

func main() {
	// --- Adapters (framework layer) ---
	repo := postgres.NewOrderRepo()
	payment := stripe.NewPayment()
	notifier := email.NewNotifier()
	customerRepo := postgres.NewCustomerRepo()
	productRepo := postgres.NewProductRepo()
	inventory := stub.NewInventory()

	// --- Use cases (application layer) ---

	// Order use cases
	placeOrder := usecase.NewPlaceOrder(repo, payment, notifier)
	cancelOrder := usecase.NewCancelOrder(repo, payment)
	getOrder := usecase.NewGetOrder(repo)
	listOrders := usecase.NewListOrders(repo)

	// Customer use cases
	createCustomer := usecase.NewCreateCustomer(customerRepo)
	getCustomer := usecase.NewGetCustomer(customerRepo)
	updateCustomerAddress := usecase.NewUpdateCustomerAddress(customerRepo)

	// Product use cases
	createProduct := usecase.NewCreateProduct(productRepo)
	getProduct := usecase.NewGetProduct(productRepo)
	searchProducts := usecase.NewSearchProducts(productRepo)

	// --- Controller (framework layer) ---
	controller := httpctl.NewOrderController(placeOrder, listOrders, getOrder, cancelOrder)
	controller.Verify()

	// --- Concept verification: in-process use case execution ---
	fmt.Println("\n--- Concept Verification ---")

	// -- Order domain --
	fmt.Println("\n[Order Domain]")

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

	// -- Customer domain --
	fmt.Println("\n[Customer Domain]")

	customer := &domain.Customer{
		ID:        "cust-001",
		Name:      "Alice Johnson",
		Email:     "alice@example.com",
		Phone:     "+1-555-0100",
		Address:   domain.Address{Street: "123 Main St", City: "Springfield", Country: "US"},
		CreatedAt: time.Now(),
		Status:    domain.CustomerActive,
	}

	if err := createCustomer.Execute(customer); err != nil {
		fmt.Printf("CreateCustomer failed: %v\n", err)
		return
	}
	fmt.Printf("CreateCustomer succeeded: %s\n", customer.ID)

	foundCust, err := getCustomer.Execute("cust-001")
	if err != nil {
		fmt.Printf("GetCustomer failed: %v\n", err)
		return
	}
	fmt.Printf("GetCustomer: %s name=%s email=%s\n", foundCust.ID, foundCust.Name, foundCust.Email)

	newAddr := domain.Address{Street: "456 Oak Ave", City: "Shelbyville", Country: "US"}
	if err := updateCustomerAddress.Execute("cust-001", newAddr); err != nil {
		fmt.Printf("UpdateCustomerAddress failed: %v\n", err)
		return
	}
	fmt.Printf("UpdateCustomerAddress succeeded: street=%s\n", newAddr.Street)

	// -- Product/Catalog domain --
	fmt.Println("\n[Product Domain]")

	widget := &domain.Product{
		ID:          "prod-001",
		Name:        "Widget",
		Description: "A fine widget",
		Price:       domain.Money{Amount: 25.00, Currency: "USD"},
		CategoryID:  "cat-1",
		Stock:       100,
	}

	gadget := &domain.Product{
		ID:          "prod-002",
		Name:        "Gadget",
		Description: "A fancy gadget",
		Price:       domain.Money{Amount: 50.00, Currency: "USD"},
		CategoryID:  "cat-1",
		Stock:       42,
	}

	if err := createProduct.Execute(widget); err != nil {
		fmt.Printf("CreateProduct failed: %v\n", err)
		return
	}
	fmt.Printf("CreateProduct succeeded: %s\n", widget.ID)

	if err := createProduct.Execute(gadget); err != nil {
		fmt.Printf("CreateProduct failed: %v\n", err)
		return
	}
	fmt.Printf("CreateProduct succeeded: %s\n", gadget.ID)

	foundProd, err := getProduct.Execute("prod-001")
	if err != nil {
		fmt.Printf("GetProduct failed: %v\n", err)
		return
	}
	fmt.Printf("GetProduct: %s name=%s price=%.2f %s stock=%d\n",
		foundProd.ID, foundProd.Name, foundProd.Price.Amount, foundProd.Price.Currency, foundProd.Stock)

	results, err := searchProducts.Execute("gadget")
	if err != nil {
		fmt.Printf("SearchProducts failed: %v\n", err)
		return
	}
	fmt.Printf("SearchProducts(\"gadget\"): %d result(s)\n", len(results))

	// -- Inventory check --
	available, err := inventory.Check("prod-001", 5)
	if err != nil {
		fmt.Printf("InventoryCheck failed: %v\n", err)
		return
	}
	fmt.Printf("InventoryCheck(prod-001, qty=5): available=%v\n", available)

	// --- HTTP server (optional, uncomment to run) ---
	// mux := http.NewServeMux()
	// controller.RegisterRoutes(mux)
	// fmt.Println("\nListening on :8080")
	// http.ListenAndServe(":8080", mux)
	_ = http.NewServeMux // suppress unused import
}

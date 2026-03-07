// E-Commerce Platform — Go Feature-Sliced Clean Architecture example.
//
// Wiring corresponds to: compose ECommerceWiring
//
//	bind OrderRepository   -> InMemoryOrderRepo
//	bind ProductRepository -> InMemoryProductRepo
//	bind ProductSearch     -> InMemoryProductRepo
//	bind PaymentGateway    -> StubPaymentGateway
//	bind PaymentRepository -> InMemoryPaymentRepo
//	entry PlaceOrder, CancelOrder, GetOrder, ListOrders
//	entry CreateProduct, GetProduct, SearchProducts
//	entry ProcessPayment, GetPayment
package main

import (
	"fmt"

	shareddomain "github.com/example/ecommerce/internal/shared/domain"

	"github.com/example/ecommerce/internal/catalog"
	catalogdomain "github.com/example/ecommerce/internal/catalog/domain"

	"github.com/example/ecommerce/internal/order"
	orderdomain "github.com/example/ecommerce/internal/order/domain"

	"github.com/example/ecommerce/internal/payment"
)

func main() {
	// --- Adapters (framework layer) via feature facades ---
	orderRepo := order.NewInMemoryRepo()
	productRepo := catalog.NewInMemoryProductRepo()
	paymentGateway := payment.NewStubGateway()
	paymentRepo := payment.NewInMemoryRepo()

	// --- Use cases (application layer) via feature facades ---

	// Order use cases
	placeOrder := order.NewPlaceOrder(orderRepo, paymentGateway)
	cancelOrder := order.NewCancelOrder(orderRepo)
	getOrder := order.NewGetOrder(orderRepo)
	listOrders := order.NewListOrders(orderRepo)

	// Catalog use cases
	createProduct := catalog.NewCreateProduct(productRepo)
	getProduct := catalog.NewGetProduct(productRepo)
	searchProducts := catalog.NewSearchProducts(productRepo)

	// Payment use cases
	processPayment := payment.NewProcessPayment(paymentGateway, paymentRepo)
	getPayment := payment.NewGetPayment(paymentRepo)

	// --- Concept verification: in-process use case execution ---
	fmt.Println("\n--- Concept Verification: Feature-Sliced E-Commerce ---")

	// -- Catalog: create products --
	fmt.Println("\n[Catalog Feature]")

	widget := &catalogdomain.Product{
		ID:          "prod-001",
		Name:        "Widget",
		Description: "A fine widget",
		Price:       shareddomain.Money{Amount: 25.00, Currency: "USD"},
		CategoryID:  "cat-1",
		Stock:       100,
	}

	gadget := &catalogdomain.Product{
		ID:          "prod-002",
		Name:        "Gadget",
		Description: "A fancy gadget",
		Price:       shareddomain.Money{Amount: 50.00, Currency: "USD"},
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

	// -- Order: place an order using catalog products --
	fmt.Println("\n[Order Feature]")

	o := &orderdomain.Order{
		ID:         "ord-001",
		CustomerID: "cust-001",
		Items: []orderdomain.OrderItem{
			{ProductID: "prod-001", Name: "Widget", Quantity: 2, Price: shareddomain.Money{Amount: 25.00, Currency: "USD"}},
			{ProductID: "prod-002", Name: "Gadget", Quantity: 1, Price: shareddomain.Money{Amount: 50.00, Currency: "USD"}},
		},
		Shipping: shareddomain.Address{Street: "123 Main St", City: "Springfield", Country: "US", Zip: "62701"},
		Status:   orderdomain.StatusPending,
	}

	orderID, err := placeOrder.Execute(order.PlaceOrderInput{
		Order:        o,
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

	// -- Payment: process payment for the order --
	fmt.Println("\n[Payment Feature]")

	paymentID, err := processPayment.Execute(payment.ProcessPaymentInput{
		OrderID:      "ord-001",
		Amount:       shareddomain.Money{Amount: 100.00, Currency: "USD"},
		PaymentToken: "tok_test_456",
	})
	if err != nil {
		fmt.Printf("ProcessPayment failed: %v\n", err)
		return
	}
	fmt.Printf("ProcessPayment succeeded: %s\n", paymentID)

	foundPayment, err := getPayment.Execute("ord-001")
	if err != nil {
		fmt.Printf("GetPayment failed: %v\n", err)
		return
	}
	fmt.Printf("GetPayment: %s orderId=%s amount=%.2f %s status=%s\n",
		foundPayment.ID, foundPayment.OrderID,
		foundPayment.Amount.Amount, foundPayment.Amount.Currency,
		foundPayment.Status)

	// -- Order: cancel the order --
	fmt.Println("\n[Order Feature — Cancel]")

	if err := cancelOrder.Execute(orderID); err != nil {
		fmt.Printf("CancelOrder failed: %v\n", err)
		return
	}
	fmt.Printf("CancelOrder succeeded: %s\n", orderID)

	found, _ = getOrder.Execute(orderID)
	fmt.Printf("GetOrder after cancel: status=%s\n", found.Status)
}

package http

import (
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/example/order-service/domain"
	"github.com/example/order-service/usecase"
)

// OrderController handles HTTP requests for orders.
// Corresponds to: adapter OrderController : framework
//   route POST   /orders      -> PlaceOrder
//   route GET    /orders      -> ListOrders
//   route GET    /orders/:id  -> GetOrder
//   route DELETE /orders/:id  -> CancelOrder
type OrderController struct {
	placeOrder  *usecase.PlaceOrder
	listOrders  *usecase.ListOrders
	getOrder    *usecase.GetOrder
	cancelOrder *usecase.CancelOrder
}

func NewOrderController(
	placeOrder *usecase.PlaceOrder,
	listOrders *usecase.ListOrders,
	getOrder *usecase.GetOrder,
	cancelOrder *usecase.CancelOrder,
) *OrderController {
	return &OrderController{
		placeOrder:  placeOrder,
		listOrders:  listOrders,
		getOrder:    getOrder,
		cancelOrder: cancelOrder,
	}
}

func (c *OrderController) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /orders", c.handlePlaceOrder)
	mux.HandleFunc("GET /orders", c.handleListOrders)
	mux.HandleFunc("GET /orders/{id}", c.handleGetOrder)
	mux.HandleFunc("DELETE /orders/{id}", c.handleCancelOrder)
}

func (c *OrderController) handlePlaceOrder(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Order        domain.Order `json:"order"`
		PaymentToken string       `json:"paymentToken"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	orderID, err := c.placeOrder.Execute(usecase.PlaceOrderInput{
		Order:        &req.Order,
		PaymentToken: req.PaymentToken,
	})
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnprocessableEntity)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"orderId": orderID})
}

func (c *OrderController) handleListOrders(w http.ResponseWriter, _ *http.Request) {
	orders, err := c.listOrders.Execute()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(orders)
}

func (c *OrderController) handleGetOrder(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	order, err := c.getOrder.Execute(id)
	if err != nil {
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(order)
}

func (c *OrderController) handleCancelOrder(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if err := c.cancelOrder.Execute(id); err != nil {
		http.Error(w, err.Error(), http.StatusUnprocessableEntity)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// Verify prints wiring information.
func (c *OrderController) Verify() {
	fmt.Println("OrderController wired:")
	fmt.Println("  POST   /orders      -> PlaceOrder")
	fmt.Println("  GET    /orders      -> ListOrders")
	fmt.Println("  GET    /orders/{id} -> GetOrder")
	fmt.Println("  DELETE /orders/{id} -> CancelOrder")
}

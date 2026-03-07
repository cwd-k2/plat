package domain

// Address is a value object.
// Corresponds to: model Address : enterprise (value object)
type Address struct {
	Street  string
	City    string
	Country string
	Zip     string
}

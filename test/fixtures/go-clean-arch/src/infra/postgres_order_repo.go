package infra

import (
	"database/sql"
	"example/domain"
)

type PostgresOrderRepo struct {
	db *sql.DB
}

func NewPostgresOrderRepo(db *sql.DB) *PostgresOrderRepo {
	return &PostgresOrderRepo{db: db}
}

func (r *PostgresOrderRepo) Save(order domain.Order) error {
	return nil
}

func (r *PostgresOrderRepo) FindByID(id string) (domain.Order, error) {
	return domain.Order{}, nil
}

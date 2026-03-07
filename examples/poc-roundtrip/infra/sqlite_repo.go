package infra

import (
	"database/sql"

	"example.com/todo/domain"
)

type SQLiteTaskRepo struct {
	db *sql.DB
}

func NewSQLiteTaskRepo(db *sql.DB) *SQLiteTaskRepo {
	return &SQLiteTaskRepo{db: db}
}

func (r *SQLiteTaskRepo) Save(task *domain.Task) error {
	return nil // stub
}

func (r *SQLiteTaskRepo) FindByID(id string) (*domain.Task, error) {
	return nil, nil // stub
}

func (r *SQLiteTaskRepo) ListAll() ([]*domain.Task, error) {
	return nil, nil // stub
}

func (r *SQLiteTaskRepo) Delete(id string) error {
	return nil // stub
}

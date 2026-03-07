package port

import "example.com/todo/domain"

type TaskRepository interface {
	Save(task *domain.Task) error
	FindByID(id string) (*domain.Task, error)
	ListAll() ([]*domain.Task, error)
	Delete(id string) error
}

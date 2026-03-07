package usecase

import (
	"example.com/todo/domain"
	"example.com/todo/port"
)

type ListTasks struct {
	repo port.TaskRepository
}

func NewListTasks(repo port.TaskRepository) *ListTasks {
	return &ListTasks{repo: repo}
}

func (uc *ListTasks) Execute() ([]*domain.Task, error) {
	return uc.repo.ListAll()
}

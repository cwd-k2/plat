package usecase

import (
	"time"

	"example.com/todo/domain"
	"example.com/todo/port"
)

type CreateTask struct {
	repo     port.TaskRepository
	notifier port.Notifier
}

func NewCreateTask(repo port.TaskRepository, notifier port.Notifier) *CreateTask {
	return &CreateTask{repo: repo, notifier: notifier}
}

func (uc *CreateTask) Execute(title, description string, priority domain.Priority) (*domain.Task, error) {
	task := &domain.Task{
		ID:          generateID(),
		Title:       title,
		Description: description,
		Priority:    priority,
		Done:        false,
		CreatedAt:   time.Now(),
	}
	if err := uc.repo.Save(task); err != nil {
		return nil, err
	}
	_ = uc.notifier.NotifyCreated(task.ID, task.Title)
	return task, nil
}

func generateID() string { return "todo-001" }

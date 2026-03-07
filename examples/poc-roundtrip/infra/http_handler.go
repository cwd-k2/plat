package infra

type TaskHandler struct {
	createTask *CreateTaskUseCase
	listTasks  *ListTasksUseCase
}

// interfaces for dependency injection (avoids import cycle)
type CreateTaskUseCase interface {
	Execute(title, description string, priority int) (interface{}, error)
}

type ListTasksUseCase interface {
	Execute() (interface{}, error)
}

func NewTaskHandler(ct CreateTaskUseCase, lt ListTasksUseCase) *TaskHandler {
	return &TaskHandler{createTask: ct, listTasks: lt}
}

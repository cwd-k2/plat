package port

type Notifier interface {
	NotifyCreated(taskID string, title string) error
}

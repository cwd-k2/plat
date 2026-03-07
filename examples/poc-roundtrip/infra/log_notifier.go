package infra

import "fmt"

type LogNotifier struct{}

func (n *LogNotifier) NotifyCreated(taskID string, title string) error {
	fmt.Printf("task created: %s (%s)\n", taskID, title)
	return nil
}

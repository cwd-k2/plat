package domain

import "time"

type Priority int

const (
	Low Priority = iota
	Medium
	High
)

type Task struct {
	ID          string
	Title       string
	Description string
	Priority    Priority
	Done        bool
	CreatedAt   time.Time
}

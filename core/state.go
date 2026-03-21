package main

import (
	"os"
	"sync"
)

// CoreState holds the global runtime state of the mihomo core.
type CoreState struct {
	mu        sync.Mutex
	isInit    bool
	isRunning bool
	homeDir   string
	logFile   *os.File // retained so we can close it on re-init (prevents fd leak)
}

var state = &CoreState{}

func (s *CoreState) lock()   { s.mu.Lock() }
func (s *CoreState) unlock() { s.mu.Unlock() }

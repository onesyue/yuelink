package main

import (
	"fmt"
	"os"
	"sync"
)

// CoreState holds the global runtime state of the mihomo core.
type CoreState struct {
	mu        sync.Mutex
	isInit    bool
	isRunning bool
	homeDir   string
	// Retained so we can close the live core.log writer on re-init —
	// without this the OS keeps the old fd open and rotateLogFile's
	// rename under Windows silently fails.
	logWriter *rotatingLogWriter
}

var state = &CoreState{}

func (s *CoreState) lock()   { s.mu.Lock() }
func (s *CoreState) unlock() { s.mu.Unlock() }

// rotatingLogWriter is an io.Writer that rotates its target file when the
// next write would push it past maxBytes. Layout: `path` is the live
// file; `path.1` … `path.backups` are historical generations; older ones
// roll off the tail on each rotation.
//
// The rotate-*before*-write policy keeps the live file at
// maxBytes + (at most one incoming chunk), which matters because mihomo
// emits one logrus record per Write — if we rotated *after* writing we
// could overshoot by a whole record before the check fired.
//
// sync.Mutex serialises Write ↔ rotation ↔ Close. logrus fans out from
// every goroutine inside mihomo; without the lock a rotation racing a
// concurrent Write would either drop bytes or write into the just-closed
// fd.
//
// This is a deliberate tiny hand-roll in place of lumberjack so the
// static library stays small on mobile (lumberjack pulls in ~1 MB of
// deps for a single feature).
type rotatingLogWriter struct {
	mu       sync.Mutex
	path     string
	maxBytes int64
	backups  int
	file     *os.File
	size     int64 // bytes written to the current live file
	closed   bool
}

// newRotatingLogWriter opens (or creates-and-appends to) `path` and
// returns a writer that will rotate it in place. Caller is responsible
// for running the startup-time rotateLogFile first if they want the
// file shifted once before the session begins — live rotation and
// startup rotation are independent concerns.
func newRotatingLogWriter(path string, maxBytes int64, backups int) (*rotatingLogWriter, error) {
	w := &rotatingLogWriter{
		path:     path,
		maxBytes: maxBytes,
		backups:  backups,
	}
	if err := w.openLocked(); err != nil {
		return nil, err
	}
	return w, nil
}

// openLocked opens the live file for append and primes `size` from the
// current file length. Callers must hold `mu` (or be the constructor,
// which runs before any other goroutine can observe the value).
func (w *rotatingLogWriter) openLocked() error {
	f, err := os.OpenFile(w.path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return err
	}
	info, err := f.Stat()
	if err != nil {
		_ = f.Close()
		return err
	}
	w.file = f
	w.size = info.Size()
	return nil
}

// Write implements io.Writer. A chunk larger than maxBytes on its own
// is still written in full — rotation only resets the size counter so
// subsequent small chunks don't pile on top of a single-record overflow.
func (w *rotatingLogWriter) Write(p []byte) (int, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.closed {
		return 0, os.ErrClosed
	}
	if w.file == nil {
		if err := w.openLocked(); err != nil {
			return 0, err
		}
	}
	// Rotate *before* writing. `w.size > 0` guards the degenerate case
	// of a huge first write to an empty file: rotating an empty live
	// file just churns `path.1` with zero-length content.
	if w.size > 0 && w.size+int64(len(p)) > w.maxBytes {
		if err := w.rotateLocked(); err != nil {
			return 0, err
		}
	}
	n, err := w.file.Write(p)
	w.size += int64(n)
	return n, err
}

// rotateLocked shifts historical generations up (.N-1 → .N, …, .1 → .2),
// renames the live file to `.1`, and reopens an empty live file. Called
// with `mu` held.
//
// Every rename step goes through renameReplace so Windows, where
// os.Rename fails if the destination exists, behaves the same as
// POSIX. On any rename failure rotateLocked returns without creating
// the fresh live file — the caller path (Write) then sees the error
// and, on the next record, openLocked reopens w.path in O_APPEND
// mode, so a transient lock (antivirus scan, Dropbox indexer) costs a
// skipped rotation rather than truncating the log.
func (w *rotatingLogWriter) rotateLocked() error {
	if w.file != nil {
		_ = w.file.Close()
		w.file = nil
	}
	// Shift from the tail inward so .1 is renamed last, avoiding a
	// collision on .2 when `backups == 2`.
	for i := w.backups - 1; i >= 1; i-- {
		src := fmt.Sprintf("%s.%d", w.path, i)
		dst := fmt.Sprintf("%s.%d", w.path, i+1)
		if err := renameReplace(src, dst); err != nil {
			return fmt.Errorf("rotate %s -> %s: %w", src, dst, err)
		}
	}
	if err := renameReplace(w.path, w.path+".1"); err != nil {
		// CRITICAL: do not O_TRUNC the live file below if we couldn't
		// move it aside — that would destroy the very bytes we're
		// trying to preserve by rotating.
		return fmt.Errorf("rotate live -> .1: %w", err)
	}
	// Live file no longer exists under `path` — O_TRUNC is redundant
	// but cheap and defends against a race where the rename lost.
	f, err := os.OpenFile(w.path, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	w.file = f
	w.size = 0
	return nil
}

// renameReplace renames `src` to `dst`, first removing any existing
// `dst` so Windows — where os.Rename fails when the destination exists
// — matches POSIX semantics. Missing `src` is a no-op (dst stays
// untouched); a locked `dst` that Remove can't clear surfaces as an
// error up to the caller.
//
// The src-first existence check is load-bearing: without it a missing
// src would still trigger Remove(dst) and then a noisy rename error,
// effectively clobbering dst for no reason.
func renameReplace(src, dst string) error {
	// If src doesn't exist, there's nothing to move — leave dst alone.
	if _, err := os.Stat(src); err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	if err := os.Remove(dst); err != nil && !os.IsNotExist(err) {
		return err
	}
	return os.Rename(src, dst)
}

// Close closes the underlying file and marks the writer as shut. Later
// Writes return os.ErrClosed. Safe to call more than once.
func (w *rotatingLogWriter) Close() error {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.closed {
		return nil
	}
	w.closed = true
	if w.file == nil {
		return nil
	}
	err := w.file.Close()
	w.file = nil
	return err
}

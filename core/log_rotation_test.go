package main

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

// Regression guards for live core.log rotation. The Go side must honour:
//   - rotate before any single Write crosses maxBytes
//   - promote `.1` → `.2` and never produce `.3` when backups == 2
//   - reject Write after Close
//
// Tiny synthetic thresholds (32 bytes) keep the tests fast and make the
// state transitions easy to assert on.

// countGenerations returns how many of `path`, `path.1`, `path.2`, …,
// `path.<=probe>` currently exist. Used to assert that rotation
// produces exactly the expected number of sidecars.
func countGenerations(path string, probe int) int {
	count := 0
	if _, err := os.Stat(path); err == nil {
		count++
	}
	for i := 1; i <= probe; i++ {
		if _, err := os.Stat(fmt.Sprintf("%s.%d", path, i)); err == nil {
			count++
		}
	}
	return count
}

func TestRotatingLogWriter_RotatesWhenNextWriteWouldOverflow(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "core.log")

	w, err := newRotatingLogWriter(path, 32, 2)
	if err != nil {
		t.Fatalf("newRotatingLogWriter: %v", err)
	}
	t.Cleanup(func() { _ = w.Close() })

	// Two 20-byte writes: first fits (20 ≤ 32), second would push to 40
	// and must trigger rotation before writing.
	payload := []byte("xxxxxxxxxxxxxxxxxxxx") // 20 bytes
	if _, err := w.Write(payload); err != nil {
		t.Fatalf("write 1: %v", err)
	}
	if _, err := w.Write(payload); err != nil {
		t.Fatalf("write 2: %v", err)
	}

	// path now holds only the second chunk (20 bytes); path.1 holds the
	// first chunk (20 bytes). Neither exceeds the 32-byte cap.
	liveInfo, err := os.Stat(path)
	if err != nil {
		t.Fatalf("stat live: %v", err)
	}
	if liveInfo.Size() != 20 {
		t.Fatalf("live size want=20 got=%d", liveInfo.Size())
	}
	prev1, err := os.Stat(path + ".1")
	if err != nil {
		t.Fatalf("stat .1 after rotation: %v", err)
	}
	if prev1.Size() != 20 {
		t.Fatalf(".1 size want=20 got=%d", prev1.Size())
	}
}

func TestRotatingLogWriter_PromotesGenerationsAndNeverCreatesThird(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "core.log")

	w, err := newRotatingLogWriter(path, 32, 2)
	if err != nil {
		t.Fatalf("newRotatingLogWriter: %v", err)
	}
	t.Cleanup(func() { _ = w.Close() })

	// Write 20 bytes three times. Expected timeline with cap=32, backups=2:
	//   after write A (size 20)    : path=A
	//   after write B (20+20 > 32) : path=B, .1=A
	//   after write C (20+20 > 32) : path=C, .1=B, .2=A   ← 3rd rotation
	for _, ch := range []byte{'A', 'B', 'C'} {
		buf := make([]byte, 20)
		for i := range buf {
			buf[i] = ch
		}
		if _, err := w.Write(buf); err != nil {
			t.Fatalf("write %c: %v", ch, err)
		}
	}

	// .3 must never appear — the backups=2 contract caps disk footprint.
	if _, err := os.Stat(path + ".3"); !os.IsNotExist(err) {
		t.Fatalf(".3 must not exist (err=%v)", err)
	}
	if got := countGenerations(path, 3); got != 3 {
		t.Fatalf("want 3 files (path + .1 + .2), got %d", got)
	}

	// Byte-level identity: newest chunk in `path`, oldest retained in `.2`.
	live, _ := os.ReadFile(path)
	if string(live) == "" || live[0] != 'C' {
		t.Fatalf("path should hold the latest (C) chunk, got %q", string(live))
	}
	one, _ := os.ReadFile(path + ".1")
	if len(one) == 0 || one[0] != 'B' {
		t.Fatalf(".1 should hold B, got %q", string(one))
	}
	two, _ := os.ReadFile(path + ".2")
	if len(two) == 0 || two[0] != 'A' {
		t.Fatalf(".2 should hold A (oldest retained), got %q", string(two))
	}
}

func TestRotatingLogWriter_WriteAfterCloseReturnsErrClosed(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "core.log")

	w, err := newRotatingLogWriter(path, 32, 2)
	if err != nil {
		t.Fatalf("newRotatingLogWriter: %v", err)
	}

	if err := w.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}
	// Second close must be a no-op.
	if err := w.Close(); err != nil {
		t.Fatalf("double close: %v", err)
	}

	if _, err := w.Write([]byte("ignored")); err != os.ErrClosed {
		t.Fatalf("write after close: want os.ErrClosed, got %v", err)
	}
}

func TestLogRotation_StartupBackupsTwoKeepsAtMostTwoSidecars(t *testing.T) {
	// Pure coverage of the startup-time rotateLogFile: seed a .1 and .2
	// from a prior session, then trigger one more rotation and confirm
	// the output stays at 3 files total with no .3 leaking through.
	dir := t.TempDir()
	path := filepath.Join(dir, "core.log")

	// Seed: path (big), .1 (small), .2 (small).
	if err := os.WriteFile(path, make([]byte, 100), 0o644); err != nil {
		t.Fatalf("seed path: %v", err)
	}
	if err := os.WriteFile(path+".1", []byte("old1"), 0o644); err != nil {
		t.Fatalf("seed .1: %v", err)
	}
	if err := os.WriteFile(path+".2", []byte("old2"), 0o644); err != nil {
		t.Fatalf("seed .2: %v", err)
	}

	// maxBytes=32 with path being 100 bytes → must rotate.
	rotateLogFile(path, 32, 2)

	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("path must have moved to .1 (err=%v)", err)
	}
	if _, err := os.Stat(path + ".1"); err != nil {
		t.Fatalf(".1 must exist after rotation: %v", err)
	}
	if _, err := os.Stat(path + ".2"); err != nil {
		t.Fatalf(".2 must exist after rotation: %v", err)
	}
	if _, err := os.Stat(path + ".3"); !os.IsNotExist(err) {
		t.Fatalf(".3 must not exist with backups=2 (err=%v)", err)
	}
}

func TestLogRotation_RenameReplaceOverwritesExistingDst(t *testing.T) {
	// Windows semantics: os.Rename fails when dst exists. renameReplace
	// must work regardless — this test stands in for the Windows
	// behaviour we can't exercise directly from a macOS/Linux CI host.
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	dst := filepath.Join(dir, "dst")
	if err := os.WriteFile(src, []byte("new"), 0o644); err != nil {
		t.Fatalf("seed src: %v", err)
	}
	if err := os.WriteFile(dst, []byte("stale"), 0o644); err != nil {
		t.Fatalf("seed dst: %v", err)
	}

	if err := renameReplace(src, dst); err != nil {
		t.Fatalf("renameReplace with existing dst: %v", err)
	}

	if got, _ := os.ReadFile(dst); string(got) != "new" {
		t.Fatalf("dst should hold src content, got %q", string(got))
	}
	if _, err := os.Stat(src); !os.IsNotExist(err) {
		t.Fatalf("src must be gone after rename (err=%v)", err)
	}
}

func TestLogRotation_RenameReplaceMissingSrcIsNoOp(t *testing.T) {
	// Missing src must leave dst untouched. The rotate-then-shift loop
	// relies on this when the first rotation runs against a directory
	// that has never had sidecars: shifting .1 → .2 when .1 doesn't
	// exist yet should be harmless, not clobber any .2 present.
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	dst := filepath.Join(dir, "dst")
	if err := os.WriteFile(dst, []byte("keep"), 0o644); err != nil {
		t.Fatalf("seed dst: %v", err)
	}

	if err := renameReplace(src, dst); err != nil {
		t.Fatalf("renameReplace with missing src: %v", err)
	}

	if got, _ := os.ReadFile(dst); string(got) != "keep" {
		t.Fatalf("dst must be preserved when src is missing, got %q", string(got))
	}
}

func TestRotatingLogWriter_ShiftErrorDoesNotTruncateLiveFile(t *testing.T) {
	// Regression guard for the Windows-rename fix: if any rename in
	// the rotate chain fails, rotateLocked must return the error
	// *before* opening `path` with O_TRUNC, or the live session's
	// bytes are lost.
	//
	// Forcing that failure on POSIX needs a Remove that fails with a
	// non-IsNotExist error. A non-empty directory at the destination
	// triggers ENOTEMPTY from os.Remove — which is what renameReplace
	// will try when shifting `.1` → `.2`. On Windows the same symptom
	// appears naturally whenever the dst just exists, which is the
	// production case this test stands in for.
	dir := t.TempDir()
	path := filepath.Join(dir, "core.log")

	w, err := newRotatingLogWriter(path, 32, 2)
	if err != nil {
		t.Fatalf("newRotatingLogWriter: %v", err)
	}
	t.Cleanup(func() { _ = w.Close() })

	// First chunk lives in `path` and must survive a failed rotation.
	const keep = "keep-me-keep-me-kee" // 19 bytes
	if _, err := w.Write([]byte(keep)); err != nil {
		t.Fatalf("write 1: %v", err)
	}

	// Seed .1 as a normal file (something the shift will want to move
	// aside into .2). Then make .2 a non-empty directory so
	// os.Remove(.2) inside renameReplace returns ENOTEMPTY — a
	// non-IsNotExist error, so the helper bubbles it up.
	if err := os.WriteFile(path+".1", []byte("prev"), 0o644); err != nil {
		t.Fatalf("seed .1: %v", err)
	}
	if err := os.Mkdir(path+".2", 0o755); err != nil {
		t.Fatalf("mkdir .2: %v", err)
	}
	if err := os.WriteFile(filepath.Join(path+".2", "sentinel"), []byte("x"), 0o644); err != nil {
		t.Fatalf("seed sentinel: %v", err)
	}

	// Next write crosses the 32-byte cap (19 + 19 > 32) and triggers
	// rotation. The shift .1 → .2 must fail, so Write returns an error
	// and — most importantly — `path` is not truncated.
	_, writeErr := w.Write([]byte("should-not-land-yet")) // 19 bytes
	if writeErr == nil {
		t.Fatalf("expected Write to return rotation error, got nil")
	}

	got, readErr := os.ReadFile(path)
	if readErr != nil {
		t.Fatalf("read live after failed rotation: %v", readErr)
	}
	if string(got) != keep {
		t.Fatalf("live file truncated by failed rotation: got %q want %q", string(got), keep)
	}
}

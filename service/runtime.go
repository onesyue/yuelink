package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// validatePath ensures `target` resolves to a real path inside one of the
// install-time allowlisted prefixes. Symlinks are followed via EvalSymlinks
// so the client can't escape the allowlist with symlink tricks. Returns the
// canonicalised path on success, or an error describing the rejection.
//
// Why: the helper runs as root and the client runs as the user. Without
// this gate, the client could pass `home_dir = /etc/passwd_dir` and the
// helper would happily MkdirAll there as root.
func (s *ServiceRuntime) validatePath(target string) (string, error) {
	if target == "" {
		return "", fmt.Errorf("path is empty")
	}
	if !filepath.IsAbs(target) {
		return "", fmt.Errorf("path must be absolute: %q", target)
	}

	// Clean removes ../ etc. but doesn't follow symlinks.
	clean := filepath.Clean(target)

	// Try to resolve symlinks. If the path doesn't exist yet (which is
	// allowed for home_dir on first call), fall back to its parent.
	resolved := clean
	if r, err := filepath.EvalSymlinks(clean); err == nil {
		resolved = r
	} else if r, err := filepath.EvalSymlinks(filepath.Dir(clean)); err == nil {
		resolved = filepath.Join(r, filepath.Base(clean))
	}

	for _, prefix := range s.cfg.AllowedHomeDirs {
		cleanPrefix := filepath.Clean(prefix)
		// Resolve symlinks in the allowlist entry too so /var vs /private/var
		// (macOS) match correctly.
		if rp, err := filepath.EvalSymlinks(cleanPrefix); err == nil {
			cleanPrefix = rp
		}
		if resolved == cleanPrefix ||
			strings.HasPrefix(resolved, cleanPrefix+string(filepath.Separator)) {
			return resolved, nil
		}
	}
	return "", fmt.Errorf(
		"path %q is not inside any allowed prefix (allowed: %v)",
		clean, s.cfg.AllowedHomeDirs,
	)
}

type ServiceRuntime struct {
	cfg *Config

	opMu sync.Mutex
	mu   sync.Mutex

	child     *exec.Cmd
	childDone chan struct{}
	pid       int

	homeDir    string
	configPath string
	logPath    string
	startedAt  time.Time
	lastExit   string
	lastError  string

	// Watchdog: auto-restart on unexpected exit
	lastStartReq   startRequest // cached for restart
	watchdogCancel context.CancelFunc
	crashCount     int
	crashWindowEnd time.Time
}

func NewServiceRuntime(cfg *Config) (*ServiceRuntime, error) {
	return &ServiceRuntime{cfg: cfg}, nil
}

// Run accepts an already-bound listener and a handler (possibly wrapped
// with auth middleware by the transport layer). The Unix-socket transport
// passes the raw mux (peer cred check happens at accept time inside the
// listener wrapper), while the HTTP transport wraps the mux with
// withTokenAuth.
func (s *ServiceRuntime) Run(ctx context.Context, listener net.Listener, handler http.Handler) error {
	server := &http.Server{
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		<-ctx.Done()
		s.opMu.Lock()
		if err := s.stopCurrentProcessLocked(); err != nil {
			log.Printf("[service] stop child during shutdown: %v", err)
		}
		s.opMu.Unlock()

		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdownCtx)
	}()

	log.Printf("[service] serving on %s", listener.Addr())
	err := server.Serve(listener)
	if err == nil || errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}

func (s *ServiceRuntime) startMihomo(req startRequest) (statusResponse, error) {
	if req.HomeDir == "" {
		return statusResponse{}, fmt.Errorf("missing home_dir")
	}
	if req.ConfigPath == "" {
		return statusResponse{}, fmt.Errorf("missing config_path")
	}

	// Validate both paths against the install-time allowlist BEFORE any
	// privileged operation. Reject early if either is outside.
	cleanHome, err := s.validatePath(req.HomeDir)
	if err != nil {
		return statusResponse{}, fmt.Errorf("home_dir rejected: %w", err)
	}
	cleanCfg, err := s.validatePath(req.ConfigPath)
	if err != nil {
		return statusResponse{}, fmt.Errorf("config_path rejected: %w", err)
	}
	// Sanity: config file must actually exist (the client wrote it before
	// calling start). Helper does NOT accept raw content anymore.
	if st, err := os.Stat(cleanCfg); err != nil || st.IsDir() {
		return statusResponse{}, fmt.Errorf("config_path is not a regular file: %q", cleanCfg)
	}
	req.HomeDir = cleanHome
	req.ConfigPath = cleanCfg

	s.opMu.Lock()
	defer s.opMu.Unlock()

	if err := s.stopCurrentProcessLocked(); err != nil {
		return statusResponse{}, err
	}

	return s.startMihomoInternal(req)
}

// startMihomoInternal does the actual start work. Caller must hold opMu and
// has already validated req paths via validatePath().
func (s *ServiceRuntime) startMihomoInternal(req startRequest) (statusResponse, error) {
	if err := os.MkdirAll(req.HomeDir, 0o755); err != nil {
		return statusResponse{}, fmt.Errorf("mkdir home_dir: %w", err)
	}

	// Use the client-supplied (already validated) config path directly.
	// Helper no longer writes config content from a request body — that
	// closes the "raw YAML from network → root file" surface.
	configPath := req.ConfigPath

	logPath := filepath.Join(req.HomeDir, "mihomo-service.log")
	logFile, err := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return statusResponse{}, fmt.Errorf("open mihomo log: %w", err)
	}

	cmd := exec.Command(s.cfg.MihomoPath, "-d", req.HomeDir, "-f", configPath)
	cmd.Stdout = logFile
	cmd.Stderr = logFile
	prepareChildProcess(cmd)

	if err := cmd.Start(); err != nil {
		_ = logFile.Close()
		s.mu.Lock()
		s.lastError = err.Error()
		s.mu.Unlock()
		return statusResponse{}, fmt.Errorf("start mihomo: %w", err)
	}

	done := make(chan struct{})
	s.mu.Lock()
	s.child = cmd
	s.childDone = done
	s.pid = cmd.Process.Pid
	s.homeDir = req.HomeDir
	s.configPath = configPath
	s.logPath = logPath
	s.startedAt = time.Now().UTC()
	s.lastError = ""
	s.lastExit = ""
	s.lastStartReq = req
	s.mu.Unlock()

	// Start watchdog context for this session
	if s.watchdogCancel != nil {
		s.watchdogCancel()
	}
	wdCtx, wdCancel := context.WithCancel(context.Background())
	s.watchdogCancel = wdCancel

	go s.waitForChild(cmd, done, logFile, wdCtx)
	log.Printf("[service] started mihomo pid=%d home=%s", cmd.Process.Pid, req.HomeDir)
	return s.statusSnapshot(), nil
}

func (s *ServiceRuntime) stopMihomo() (statusResponse, error) {
	s.opMu.Lock()
	defer s.opMu.Unlock()

	err := s.stopCurrentProcessLocked()
	return s.statusSnapshot(), err
}

func (s *ServiceRuntime) stopCurrentProcessLocked() error {
	// Cancel watchdog so it doesn't auto-restart after explicit stop
	if s.watchdogCancel != nil {
		s.watchdogCancel()
		s.watchdogCancel = nil
	}

	// Explicit stop is not a crash — reset the rolling crash counter so
	// a future unrelated crash doesn't get attributed to this session's
	// accumulated count. Without this, a long-lived helper that has
	// auto-restarted a few times will hit the 10-crashes-per-window
	// give-up threshold sooner than the operator expects after they
	// manually cycle the connection.
	s.mu.Lock()
	s.crashCount = 0
	s.crashWindowEnd = time.Time{}
	s.mu.Unlock()

	cmd, done := s.currentChild()
	if cmd == nil || cmd.Process == nil {
		return nil
	}

	log.Printf("[service] stopping mihomo pid=%d", cmd.Process.Pid)

	if err := terminateProcess(cmd); err != nil {
		return err
	}

	select {
	case <-done:
		return nil
	case <-time.After(5 * time.Second):
		log.Printf("[service] graceful stop timed out for pid=%d, forcing kill", cmd.Process.Pid)
		if err := killProcess(cmd); err != nil {
			return err
		}
		select {
		case <-done:
			return nil
		case <-time.After(3 * time.Second):
			return fmt.Errorf("mihomo pid=%d did not exit after kill", cmd.Process.Pid)
		}
	}
}

func (s *ServiceRuntime) currentChild() (*exec.Cmd, chan struct{}) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.child, s.childDone
}

// Watchdog constants (matches CVR: max 10 crashes in 10 minutes)
const (
	watchdogMaxCrashes = 10
	watchdogWindow     = 10 * time.Minute
	watchdogBaseDelay  = 2 * time.Second
	watchdogMaxDelay   = 30 * time.Second
)

func (s *ServiceRuntime) waitForChild(cmd *exec.Cmd, done chan struct{}, logFile *os.File, wdCtx context.Context) {
	err := cmd.Wait()
	exitText := fmt.Sprintf("exited at %s", time.Now().UTC().Format(time.RFC3339))
	if err != nil {
		exitText = fmt.Sprintf("%s (%v)", exitText, err)
	}

	s.mu.Lock()
	isCurrentChild := s.child == cmd
	if isCurrentChild {
		s.child = nil
		s.childDone = nil
		s.pid = 0
		s.lastExit = exitText
		if err != nil {
			s.lastError = err.Error()
		}
	}
	cachedReq := s.lastStartReq
	s.mu.Unlock()

	_ = logFile.Close()
	close(done)
	log.Printf("[service] mihomo %s", exitText)

	// Watchdog: auto-restart if the exit was unexpected (context not cancelled)
	if !isCurrentChild {
		return
	}
	select {
	case <-wdCtx.Done():
		log.Printf("[watchdog] explicit stop — no restart")
		return
	default:
	}

	// Crash window tracking — guarded by s.mu because stopCurrentProcessLocked
	// resets the counter on explicit stop (see #8 fix). Reading the snapshot
	// once under the lock avoids a torn read between counter and threshold.
	s.mu.Lock()
	now := time.Now()
	if now.After(s.crashWindowEnd) {
		s.crashCount = 0
		s.crashWindowEnd = now.Add(watchdogWindow)
	}
	s.crashCount++
	currentCount := s.crashCount
	s.mu.Unlock()

	if currentCount > watchdogMaxCrashes {
		log.Printf("[watchdog] %d crashes in window — giving up", currentCount)
		return
	}

	// Exponential backoff: 2s, 4s, 8s, 16s, 30s cap
	delay := watchdogBaseDelay
	for i := 1; i < currentCount; i++ {
		delay *= 2
		if delay > watchdogMaxDelay {
			delay = watchdogMaxDelay
			break
		}
	}

	log.Printf("[watchdog] crash #%d — restarting in %v", currentCount, delay)
	select {
	case <-time.After(delay):
	case <-wdCtx.Done():
		log.Printf("[watchdog] cancelled during backoff wait")
		return
	}

	// Re-check context before restarting
	select {
	case <-wdCtx.Done():
		return
	default:
	}

	s.opMu.Lock()
	_, restartErr := s.startMihomoInternal(cachedReq)
	s.opMu.Unlock()
	if restartErr != nil {
		log.Printf("[watchdog] restart failed: %v", restartErr)
	}
}

func (s *ServiceRuntime) statusSnapshot() statusResponse {
	s.mu.Lock()
	defer s.mu.Unlock()

	var startedAt string
	if !s.startedAt.IsZero() {
		startedAt = s.startedAt.Format(time.RFC3339)
	}

	return statusResponse{
		Running:    s.child != nil && s.pid > 0,
		Pid:        s.pid,
		HomeDir:    s.homeDir,
		ConfigPath: s.configPath,
		LogPath:    s.logPath,
		StartedAt:  startedAt,
		LastExit:   s.lastExit,
		LastError:  s.lastError,
	}
}

func (s *ServiceRuntime) readLogs(lines int) logsResponse {
	s.mu.Lock()
	path := s.logPath
	s.mu.Unlock()

	content, err := tailFile(path, lines)
	if err != nil {
		return logsResponse{
			LogPath: path,
			Content: "",
			Error:   err.Error(),
		}
	}

	return logsResponse{
		LogPath: path,
		Content: content,
	}
}

func tailFile(path string, lines int) (string, error) {
	if path == "" {
		return "", nil
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}

	if lines <= 0 {
		return string(raw), nil
	}

	all := splitLines(string(raw))
	if len(all) <= lines {
		return string(raw), nil
	}
	return joinLines(all[len(all)-lines:]), nil
}

func splitLines(content string) []string {
	if content == "" {
		return nil
	}
	normalized := strings.ReplaceAll(content, "\r\n", "\n")
	normalized = strings.ReplaceAll(normalized, "\r", "\n")
	return strings.Split(normalized, "\n")
}

func joinLines(lines []string) string {
	if len(lines) == 0 {
		return ""
	}
	result := lines[0]
	for _, line := range lines[1:] {
		result += "\n" + line
	}
	return result
}

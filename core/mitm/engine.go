package mitm

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"sync"
	"time"
)

const (
	defaultMITMPort = 9091
	shutdownTimeout = 5 * time.Second
	healthCheckPath = "/ping"
)

// Engine is the MITM proxy engine.
type Engine struct {
	port      int
	server    *http.Server
	listener  net.Listener
	running   bool
	startedAt *time.Time
	lastError string
	mu        sync.Mutex
}

// NewEngine creates a new engine with the given preferred port.
// Pass 0 to use the default port (9091).
func NewEngine(port int) *Engine {
	if port <= 0 {
		port = defaultMITMPort
	}
	return &Engine{port: port}
}

// Start starts the engine. Tries the preferred port first; falls back to an
// OS-assigned port if the preferred port is busy. Updates e.port with the
// actual bound port.
func (e *Engine) Start() error {
	e.mu.Lock()
	defer e.mu.Unlock()

	if e.running {
		return fmt.Errorf("[MITM] engine is already running on port %d", e.port)
	}

	// Try preferred port, then fall back to OS-assigned.
	preferredAddr := fmt.Sprintf("127.0.0.1:%d", e.port)
	ln, err := net.Listen("tcp", preferredAddr)
	if err != nil {
		logEngine("preferred port %d busy, falling back to OS-assigned port", e.port)
		ln, err = net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			return fmt.Errorf("[MITM] cannot bind: %w", err)
		}
	}

	// Record the actual port from the listener.
	e.port = ln.Addr().(*net.TCPAddr).Port
	e.listener = ln

	mux := http.NewServeMux()

	// Health-check endpoint.
	mux.HandleFunc(healthCheckPath, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"ok","engine":"YueLink Module Runtime"}`))
	})

	// All other requests (including CONNECT) go to the main handler.
	mux.HandleFunc("/", e.handleRequest)

	e.server = &http.Server{
		Handler: mux,
	}

	logEngine("starting on 127.0.0.1:%d", e.port)

	// Serve on the pre-bound listener so we own the port immediately.
	go func() {
		if serveErr := e.server.Serve(ln); serveErr != nil && serveErr != http.ErrServerClosed {
			e.mu.Lock()
			e.lastError = serveErr.Error()
			e.running = false
			e.startedAt = nil
			e.mu.Unlock()
			logEngine("serve error: %v", serveErr)
		}
	}()

	now := time.Now().UTC()
	e.startedAt = &now
	e.running = true
	e.lastError = ""
	logEngine("started on 127.0.0.1:%d", e.port)
	return nil
}

// Stop gracefully stops the engine with a 5-second timeout.
func (e *Engine) Stop() error {
	e.mu.Lock()
	defer e.mu.Unlock()

	if !e.running {
		return nil // idempotent
	}

	logEngine("stopping …")
	ctx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()

	if err := e.server.Shutdown(ctx); err != nil {
		return fmt.Errorf("[MITM] shutdown error: %w", err)
	}

	e.running = false
	e.startedAt = nil
	e.server = nil
	e.listener = nil
	logEngine("stopped")
	return nil
}

// IsRunning returns the current running state.
func (e *Engine) IsRunning() bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.running
}

// Port returns the actual bound port (valid after Start succeeds).
func (e *Engine) Port() int {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.port
}

// HealthCheck pings the engine's own /ping endpoint to verify it is actually
// responding to connections. Returns nil if healthy.
func (e *Engine) HealthCheck() error {
	e.mu.Lock()
	port := e.port
	running := e.running
	e.mu.Unlock()

	if !running {
		return fmt.Errorf("[MITM] engine not running")
	}

	url := fmt.Sprintf("http://127.0.0.1:%d%s", port, healthCheckPath)
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return fmt.Errorf("[MITM] health check failed: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("[MITM] health check returned HTTP %d", resp.StatusCode)
	}
	return nil
}

// Status returns a MitmEngineStatus snapshot.
func (e *Engine) Status() MitmEngineStatus {
	e.mu.Lock()
	defer e.mu.Unlock()

	addr := ""
	if e.running {
		addr = fmt.Sprintf("127.0.0.1:%d", e.port)
	}

	healthy := false
	if e.running {
		// Non-blocking health probe: dial the port rather than doing an HTTP GET
		// (avoids a recursive lock). A successful dial is a good-enough liveness
		// check inside a lock-free fast path; callers that need the full HTTP
		// probe can call HealthCheck() directly.
		conn, dialErr := net.DialTimeout("tcp", addr, 200*time.Millisecond)
		if dialErr == nil {
			conn.Close()
			healthy = true
		}
	}

	return MitmEngineStatus{
		Running:   e.running,
		Port:      e.port,
		Address:   addr,
		StartedAt: e.startedAt,
		Healthy:   healthy,
		LastError: e.lastError,
	}
}

// handleRequest dispatches incoming proxy requests.
// CONNECT → passthrough tunnel (Phase 1, no MITM interception yet).
// Anything else → 501.
func (e *Engine) handleRequest(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodConnect {
		e.handleConnect(w, r)
		return
	}
	logEngine("unsupported method %s %s (Phase 1 passthrough only)", r.Method, r.RequestURI)
	http.Error(w, "Method Not Allowed — YueLink Module Runtime Phase 1", http.StatusNotImplemented)
}

// handleConnect tunnels a CONNECT request without interception.
// Phase 1: logs the target host, hijacks the connection, dials the remote,
// and copies bytes in both directions.
func (e *Engine) handleConnect(w http.ResponseWriter, r *http.Request) {
	logEngine("CONNECT %s (passthrough, Phase 1)", r.Host)

	hj, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "hijacking not supported", http.StatusInternalServerError)
		return
	}

	clientConn, _, err := hj.Hijack()
	if err != nil {
		logEngine("CONNECT hijack error: %v", err)
		return
	}
	defer clientConn.Close()

	// Respond 200 Connection Established.
	if _, werr := clientConn.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n")); werr != nil {
		logEngine("CONNECT write 200 error: %v", werr)
		return
	}

	// Dial the upstream target.
	targetConn, err := net.DialTimeout("tcp", r.Host, 10*time.Second)
	if err != nil {
		logEngine("CONNECT dial %s failed: %v", r.Host, err)
		return
	}
	defer targetConn.Close()

	// Bidirectional copy until either side closes.
	done := make(chan struct{}, 2)
	pipe := func(dst net.Conn, src net.Conn) {
		buf := make([]byte, 32*1024)
		for {
			n, readErr := src.Read(buf)
			if n > 0 {
				if _, writeErr := dst.Write(buf[:n]); writeErr != nil {
					break
				}
			}
			if readErr != nil {
				break
			}
		}
		done <- struct{}{}
	}
	go pipe(targetConn, clientConn)
	go pipe(clientConn, targetConn)
	<-done
}

// ---------------------------------------------------------------------------
// Global singleton for FFI access
// ---------------------------------------------------------------------------

var (
	globalEngineMu sync.Mutex
	globalEngine   *Engine
)

// StartMITMEngine starts the global MITM engine singleton on the given port.
// Pass 0 to use the default port.
func StartMITMEngine(port int) error {
	globalEngineMu.Lock()
	defer globalEngineMu.Unlock()

	if globalEngine != nil && globalEngine.IsRunning() {
		return fmt.Errorf("[MITM] global engine already running")
	}
	globalEngine = NewEngine(port)
	return globalEngine.Start()
}

// StopMITMEngine stops the global MITM engine singleton.
func StopMITMEngine() error {
	globalEngineMu.Lock()
	defer globalEngineMu.Unlock()

	if globalEngine == nil {
		return nil
	}
	err := globalEngine.Stop()
	globalEngine = nil
	return err
}

// GetMITMEngineStatus returns the status of the global MITM engine.
func GetMITMEngineStatus() MitmEngineStatus {
	globalEngineMu.Lock()
	defer globalEngineMu.Unlock()

	if globalEngine == nil {
		return MitmEngineStatus{Running: false, Port: defaultMITMPort}
	}
	return globalEngine.Status()
}

// MITMEngineStatusJSON returns the current engine status serialised as JSON.
// Exported for testing convenience.
func MITMEngineStatusJSON() ([]byte, error) {
	return json.Marshal(GetMITMEngineStatus())
}

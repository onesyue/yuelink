package mitm

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"sync"
	"time"
)

const (
	defaultMITMPort = 9091
	shutdownTimeout = 5 * time.Second
)

// Engine is the MITM proxy engine.
type Engine struct {
	port    int
	server  *http.Server
	running bool
	mu      sync.Mutex
}

// NewEngine creates a new engine on the given port.
// Pass 0 to use the default port (9091).
func NewEngine(port int) *Engine {
	if port <= 0 {
		port = defaultMITMPort
	}
	return &Engine{port: port}
}

// Start starts the engine. Returns error if already running or port is busy.
func (e *Engine) Start() error {
	e.mu.Lock()
	defer e.mu.Unlock()

	if e.running {
		return fmt.Errorf("[MITM] engine is already running on port %d", e.port)
	}

	mux := http.NewServeMux()

	// Health-check endpoint.
	mux.HandleFunc("/ping", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"ok","engine":"YueLink Module Runtime"}`))
	})

	// All other requests (including CONNECT) go to the main handler.
	mux.HandleFunc("/", e.handleRequest)

	addr := fmt.Sprintf("127.0.0.1:%d", e.port)
	e.server = &http.Server{
		Addr:    addr,
		Handler: mux,
	}

	// Start listening in a goroutine; capture bind errors synchronously via
	// a small channel.
	errCh := make(chan error, 1)
	go func() {
		log.Printf("[MITM] Engine starting on %s", addr)
		if err := e.server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			errCh <- err
		} else {
			errCh <- nil
		}
	}()

	// Give the server a moment to bind; a quick error means the port is busy.
	select {
	case err := <-errCh:
		if err != nil {
			return fmt.Errorf("[MITM] failed to start engine: %w", err)
		}
		return fmt.Errorf("[MITM] engine stopped unexpectedly before accepting connections")
	case <-time.After(100 * time.Millisecond):
		// No error within 100 ms → assume bind succeeded.
	}

	e.running = true
	log.Printf("[MITM] Engine started on %s", addr)
	return nil
}

// Stop gracefully stops the engine with a 5-second timeout.
func (e *Engine) Stop() error {
	e.mu.Lock()
	defer e.mu.Unlock()

	if !e.running {
		return nil // idempotent
	}

	log.Printf("[MITM] Engine stopping …")
	ctx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()

	if err := e.server.Shutdown(ctx); err != nil {
		return fmt.Errorf("[MITM] shutdown error: %w", err)
	}

	e.running = false
	e.server = nil
	log.Printf("[MITM] Engine stopped")
	return nil
}

// IsRunning returns the current running state.
func (e *Engine) IsRunning() bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.running
}

// Status returns an EngineStatus snapshot.
func (e *Engine) Status() EngineStatus {
	e.mu.Lock()
	defer e.mu.Unlock()
	addr := ""
	if e.running {
		addr = fmt.Sprintf("127.0.0.1:%d", e.port)
	}
	return EngineStatus{
		Running: e.running,
		Port:    e.port,
		Address: addr,
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
	log.Printf("[MITM] Unsupported method %s %s (Phase 1 passthrough only)", r.Method, r.RequestURI)
	http.Error(w, "Method Not Allowed — YueLink Module Runtime Phase 1", http.StatusNotImplemented)
}

// handleConnect tunnels a CONNECT request without interception.
// Phase 1: logs the target host, hijacks the connection, dials the remote,
// and copies bytes in both directions.
func (e *Engine) handleConnect(w http.ResponseWriter, r *http.Request) {
	log.Printf("[MITM] CONNECT %s (passthrough, Phase 1)", r.Host)

	hj, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "hijacking not supported", http.StatusInternalServerError)
		return
	}

	clientConn, _, err := hj.Hijack()
	if err != nil {
		log.Printf("[MITM] CONNECT hijack error: %v", err)
		return
	}
	defer clientConn.Close()

	// Respond 200 Connection Established.
	if _, werr := clientConn.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n")); werr != nil {
		log.Printf("[MITM] CONNECT write 200 error: %v", werr)
		return
	}

	// Dial the upstream target.
	targetConn, err := net.DialTimeout("tcp", r.Host, 10*time.Second)
	if err != nil {
		log.Printf("[MITM] CONNECT dial %s failed: %v", r.Host, err)
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
func GetMITMEngineStatus() EngineStatus {
	globalEngineMu.Lock()
	defer globalEngineMu.Unlock()

	if globalEngine == nil {
		return EngineStatus{Running: false, Port: defaultMITMPort}
	}
	return globalEngine.Status()
}

// MITMEngineStatusJSON returns the current engine status serialised as JSON.
// Exported for testing convenience.
func MITMEngineStatusJSON() ([]byte, error) {
	return json.Marshal(GetMITMEngineStatus())
}

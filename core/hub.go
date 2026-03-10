package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"fmt"
	"os"
	"path/filepath"
	"unsafe"

	"github.com/metacubex/mihomo/config"
	mihomoConst "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/log"
)

// --------------------------------------------------------------------
// Lifecycle
// --------------------------------------------------------------------

// InitCore initializes the mihomo core with the given home directory.
// Sets up config paths and prepares the runtime environment.
// Returns a C string: empty string on success, error message on failure.
// Caller must free the returned string via FreeCString.
//
//export InitCore
func InitCore(homeDir *C.char) *C.char {
	state.lock()
	defer state.unlock()

	dir := C.GoString(homeDir)

	// Ensure directory exists
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return C.CString(fmt.Sprintf("MkdirAll failed: %v", err))
	}

	// Set mihomo home directory
	if !filepath.IsAbs(dir) {
		cwd, _ := os.Getwd()
		dir = filepath.Join(cwd, dir)
	}
	mihomoConst.SetHomeDir(dir)

	// Set config file to absolute path BEFORE config.Init()
	// (config.Init uses C.Path.Config() which defaults to relative "config.yaml",
	// causing file creation failures on Android where cwd is not writable)
	mihomoConst.SetConfig(filepath.Join(dir, "config.yaml"))

	// Initialize config system (creates necessary files)
	if err := config.Init(dir); err != nil {
		return C.CString(fmt.Sprintf("config.Init failed: %v", err))
	}

	state.homeDir = dir
	state.isInit = true

	return C.CString("")
}

// StartCore starts the mihomo core with the given YAML configuration.
// This starts the proxy engine, listeners, and the external-controller REST API.
// Returns a C string: empty string on success, error message on failure.
// Caller must free the returned string via FreeCString.
//
//export StartCore
func StartCore(configStr *C.char) *C.char {
	state.lock()
	defer state.unlock()

	if !state.isInit {
		return C.CString("core not initialized, call InitCore first")
	}
	if state.isRunning {
		return C.CString("")
	}

	configYaml := C.GoString(configStr)

	// Write config to file so mihomo can reload it later
	configPath := filepath.Join(state.homeDir, "config.yaml")
	if err := os.WriteFile(configPath, []byte(configYaml), 0o644); err != nil {
		return C.CString(fmt.Sprintf("write config: %v", err))
	}
	mihomoConst.SetConfig(configPath)

	// Parse and apply config via hub.Parse (starts everything)
	if err := hub.Parse([]byte(configYaml)); err != nil {
		return C.CString(fmt.Sprintf("parse config: %v", err))
	}

	state.isRunning = true
	log.Infoln("YueLink core started")
	return C.CString("")
}

// StopCore stops the mihomo core.
// Shuts down all listeners and cleans up resources.
//
//export StopCore
func StopCore() {
	state.lock()
	defer state.unlock()

	if !state.isRunning {
		return
	}

	executor.Shutdown()
	state.isRunning = false
	log.Infoln("YueLink core stopped")
}

// Shutdown fully shuts down and cleans up the core.
//
//export Shutdown
func Shutdown() {
	StopCore()
	state.lock()
	defer state.unlock()
	state.isInit = false
}

// IsRunning returns 1 if the core is running, 0 otherwise.
//
//export IsRunning
func IsRunning() C.int {
	state.lock()
	defer state.unlock()
	if state.isRunning {
		return 1
	}
	return 0
}

// --------------------------------------------------------------------
// Configuration
// --------------------------------------------------------------------

// ValidateConfig checks if the given YAML config is valid.
// Returns 0 if valid, -1 if invalid.
//
//export ValidateConfig
func ValidateConfig(configStr *C.char) C.int {
	yaml := C.GoString(configStr)

	_, err := executor.ParseWithBytes([]byte(yaml))
	if err != nil {
		return -1
	}

	return 0
}

// UpdateConfig applies a new configuration (hot reload).
// Returns a C string: empty string on success, error message on failure.
// Caller must free the returned string via FreeCString.
//
//export UpdateConfig
func UpdateConfig(configStr *C.char) *C.char {
	state.lock()
	defer state.unlock()

	if !state.isRunning {
		return C.CString("core not running")
	}

	yaml := C.GoString(configStr)

	// Write updated config
	configPath := filepath.Join(state.homeDir, "config.yaml")
	if err := os.WriteFile(configPath, []byte(yaml), 0o644); err != nil {
		return C.CString(fmt.Sprintf("write config: %v", err))
	}

	// Re-parse and apply
	if err := hub.Parse([]byte(yaml)); err != nil {
		return C.CString(fmt.Sprintf("parse config: %v", err))
	}

	log.Infoln("Config updated successfully")
	return C.CString("")
}

// --------------------------------------------------------------------
// Version
// --------------------------------------------------------------------

// GetVersion returns the mihomo version string.
// Caller must free the returned C string.
//
//export GetVersion
func GetVersion() *C.char {
	v := fmt.Sprintf("mihomo Meta %s", mihomoConst.Version)
	return C.CString(v)
}

// --------------------------------------------------------------------
// Memory management
// --------------------------------------------------------------------

// FreeCString frees a C string previously returned by this library.
//
//export FreeCString
func FreeCString(s *C.char) {
	C.free(unsafe.Pointer(s))
}

// Required main for c-shared/c-archive build mode
func main() {}

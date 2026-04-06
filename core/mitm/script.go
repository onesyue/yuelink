//go:build with_script

// script.go — goja JavaScript runtime wrapper for the YueLink Module Runtime.
//
// Build tag: with_script
// Before enabling this file, add goja to the module:
//
//	cd core && go get github.com/dop251/goja@latest
//
// Then build with: go build -tags with_script ./...

package mitm

import (
	"fmt"
	"log"
	"time"

	"github.com/dop251/goja"
)

// ScriptRuntime wraps a goja runtime with YueLink host APIs.
type ScriptRuntime struct {
	vm *goja.Runtime
}

// NewScriptRuntime creates a new JS runtime with basic host APIs registered.
//
// Registers:
//
//	console.log(msg)              → logs with [MITM][Script] prefix
//	$notification.post(t,s,b)     → stub, just logs
//	$persistentStore.read(k)      → returns "" (stub)
//	$persistentStore.write(k,v)   → no-op (stub)
func NewScriptRuntime() (*ScriptRuntime, error) {
	vm := goja.New()

	// ------------------------------------------------------------------
	// console.log
	// ------------------------------------------------------------------
	console := vm.NewObject()
	if err := console.Set("log", func(call goja.FunctionCall) goja.Value {
		var parts []interface{}
		for _, arg := range call.Arguments {
			parts = append(parts, arg.Export())
		}
		log.Printf("[MITM][Script] %v", fmt.Sprint(parts...))
		return goja.Undefined()
	}); err != nil {
		return nil, fmt.Errorf("mitm: failed to set console.log: %w", err)
	}
	if err := vm.Set("console", console); err != nil {
		return nil, fmt.Errorf("mitm: failed to set console: %w", err)
	}

	// ------------------------------------------------------------------
	// $notification.post(title, subtitle, body)
	// ------------------------------------------------------------------
	notification := vm.NewObject()
	if err := notification.Set("post", func(call goja.FunctionCall) goja.Value {
		title := ""
		subtitle := ""
		body := ""
		if len(call.Arguments) > 0 {
			title = call.Arguments[0].String()
		}
		if len(call.Arguments) > 1 {
			subtitle = call.Arguments[1].String()
		}
		if len(call.Arguments) > 2 {
			body = call.Arguments[2].String()
		}
		log.Printf("[MITM][Script] $notification.post title=%q subtitle=%q body=%q (stub)", title, subtitle, body)
		return goja.Undefined()
	}); err != nil {
		return nil, fmt.Errorf("mitm: failed to set $notification.post: %w", err)
	}
	if err := vm.Set("$notification", notification); err != nil {
		return nil, fmt.Errorf("mitm: failed to set $notification: %w", err)
	}

	// ------------------------------------------------------------------
	// $persistentStore.read(key) / $persistentStore.write(key, value)
	// ------------------------------------------------------------------
	store := vm.NewObject()
	if err := store.Set("read", func(call goja.FunctionCall) goja.Value {
		key := ""
		if len(call.Arguments) > 0 {
			key = call.Arguments[0].String()
		}
		log.Printf("[MITM][Script] $persistentStore.read key=%q → \"\" (stub)", key)
		return vm.ToValue("")
	}); err != nil {
		return nil, fmt.Errorf("mitm: failed to set $persistentStore.read: %w", err)
	}
	if err := store.Set("write", func(call goja.FunctionCall) goja.Value {
		key := ""
		value := ""
		if len(call.Arguments) > 0 {
			key = call.Arguments[0].String()
		}
		if len(call.Arguments) > 1 {
			value = call.Arguments[1].String()
		}
		log.Printf("[MITM][Script] $persistentStore.write key=%q value=%q (stub)", key, value)
		return goja.Undefined()
	}); err != nil {
		return nil, fmt.Errorf("mitm: failed to set $persistentStore.write: %w", err)
	}
	if err := vm.Set("$persistentStore", store); err != nil {
		return nil, fmt.Errorf("mitm: failed to set $persistentStore: %w", err)
	}

	return &ScriptRuntime{vm: vm}, nil
}

// Execute runs a JS string and returns the result as a string.
// The second return value is the execution time in milliseconds.
func (r *ScriptRuntime) Execute(script string) (result string, durationMs int64, err error) {
	start := time.Now()
	val, runErr := r.vm.RunString(script)
	durationMs = time.Since(start).Milliseconds()
	if runErr != nil {
		return "", durationMs, fmt.Errorf("mitm: script execution error: %w", runErr)
	}
	if val == nil || goja.IsUndefined(val) || goja.IsNull(val) {
		return "", durationMs, nil
	}
	return val.String(), durationMs, nil
}

// Destroy releases the runtime. After Destroy, the ScriptRuntime must not be used.
func (r *ScriptRuntime) Destroy() {
	r.vm.Interrupt("destroyed")
	r.vm = nil
}

// ProbeScriptRuntime runs a hello world test and returns diagnostic info.
// Used for Phase 1 verification.
// Returns: {"result": "...", "duration_ms": N, "engine": "goja"}
func ProbeScriptRuntime() (map[string]interface{}, error) {
	rt, err := NewScriptRuntime()
	if err != nil {
		return nil, fmt.Errorf("mitm: ProbeScriptRuntime: failed to create runtime: %w", err)
	}
	defer rt.Destroy()

	probe := `
(function() {
    console.log("ProbeScriptRuntime: hello from goja");
    $notification.post("YueLink", "Module Runtime", "Phase 1 probe OK");
    $persistentStore.write("probe_key", "probe_value");
    var readback = $persistentStore.read("probe_key");
    return "hello from YueLink Module Runtime; readback=" + readback;
})()
`
	result, durationMs, err := rt.Execute(probe)
	if err != nil {
		return nil, fmt.Errorf("mitm: ProbeScriptRuntime: %w", err)
	}

	log.Printf("[MITM] ProbeScriptRuntime OK: result=%q duration_ms=%d", result, durationMs)
	return map[string]interface{}{
		"result":      result,
		"duration_ms": durationMs,
		"engine":      "goja",
	}, nil
}

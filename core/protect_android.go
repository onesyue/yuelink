//go:build android

package main

/*
#include <stdlib.h>

// Defined in protect_android.c
extern int protect_fd(int fd);
*/
import "C"

import (
	"syscall"

	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/log"
)

func init() {
	// Set the socket protection hook for Android VPN.
	//
	// Every outbound socket mihomo creates (proxy connections, DNS queries,
	// etc.) goes through this hook. protect_fd() calls VpnService.protect(fd)
	// via JNI, which marks the socket to bypass VPN routing.
	//
	// Without this, outbound sockets may loop back through the TUN interface,
	// creating a routing loop where nothing reaches the internet.
	//
	// When DefaultSocketHook is set, mihomo's dialer skips interfaceName and
	// routingMark binding — protect() is the sole routing mechanism.
	dialer.DefaultSocketHook = func(network, address string, conn syscall.RawConn) error {
		var protectErr error
		err := conn.Control(func(fd uintptr) {
			ok := C.protect_fd(C.int(fd))
			if ok == 0 {
				log.Warnln("[Protect] failed to protect fd %d for %s -> %s", fd, network, address)
			}
		})
		if err != nil {
			return err
		}
		return protectErr
	}
	log.Infoln("[Protect] Android socket protection hook installed")
}

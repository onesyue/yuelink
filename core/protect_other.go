//go:build !android

package main

// No socket protection needed on non-Android platforms.
// Desktop platforms use system proxy (not TUN/VPN).
// iOS uses NEPacketTunnelProvider which handles routing internally.

// Settings-related providers.
//
// The core settings state providers (routingMode, connectionMode, logLevel,
// systemProxyOnConnect, autoConnect) are defined in core_provider.dart because
// CoreActions reads them directly. They are re-exported here for convenience so
// settings widgets can import from this single location.
//
// proxyProvidersProvider + ProxyProvidersNotifier have moved here from
// lib/providers/proxy_provider_provider.dart.

// Re-export core settings state providers (defined in core_provider.dart to
// avoid circular imports with CoreActions).
export '../../../core/providers/core_provider.dart'
    show
        routingModeProvider,
        connectionModeProvider,
        logLevelProvider,
        systemProxyOnConnectProvider,
        autoConnectProvider;

// Re-export split tunnel providers.
export 'split_tunnel_provider.dart';

// Proxy providers (remote provider management).
export 'proxy_providers_provider.dart';

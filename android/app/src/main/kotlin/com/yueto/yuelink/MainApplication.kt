package com.yueto.yuelink

import android.util.Log
import io.flutter.app.FlutterApplication
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Pre-warm a single shared FlutterEngine at process start so the Quick
 * Settings tile can toggle the VPN headlessly — without launching
 * MainActivity. The same engine is reused by:
 *
 *   - MainActivity (provideFlutterEngine override) — UI attaches to it
 *   - ProxyTileService — invokes a MethodChannel directly on it
 *
 * Only one engine in the process means only one CoreManager instance and
 * one set of FFI bindings on libclash.so. Two engines would race on the
 * Go core's single mutex and on the shared homeDir / config.yaml path.
 *
 * The engine survives MainActivity destruction because Application holds
 * a strong reference via FlutterEngineCache. It only goes away when the
 * OS kills the process (which also stops the VPN cleanly via the
 * lifecycle observer in main.dart).
 *
 * On first cold start triggered by the tile, the engine takes ~500ms to
 * 1s to initialize Dart. ProxyTileService writes a `pending_toggle` flag
 * to SharedPreferences; Dart checks it after registering the MethodChannel
 * handler and applies the queued toggle, so the click is never lost.
 */
class MainApplication : FlutterApplication() {

    companion object {
        const val SHARED_ENGINE_ID = "yuelink_shared_engine"
        private const val TAG = "YueLinkApp"
    }

    override fun onCreate() {
        super.onCreate()
        prewarmSharedEngine()
    }

    private fun prewarmSharedEngine() {
        try {
            val cache = FlutterEngineCache.getInstance()
            if (cache.get(SHARED_ENGINE_ID) != null) return
            val engine = FlutterEngine(this)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
            cache.put(SHARED_ENGINE_ID, engine)
            Log.i(TAG, "shared FlutterEngine pre-warmed")
        } catch (e: Throwable) {
            // Don't crash the app — if pre-warm fails, MainActivity will
            // create its own engine on first launch as the fallback path.
            Log.e(TAG, "shared FlutterEngine pre-warm failed", e)
        }
    }
}

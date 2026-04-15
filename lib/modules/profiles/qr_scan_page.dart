import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../i18n/app_strings.dart';
import '../../shared/telemetry.dart';
import '../../theme.dart';

/// Full-screen camera scanner that returns a URL [String] via [Navigator.pop].
///
/// Only returns when a barcode containing a URL (http:// or https://) is
/// detected. Handles camera permission denial gracefully.
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _hasResult = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasResult) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null) continue;
      if (value.startsWith('http://') || value.startsWith('https://')) {
        _hasResult = true;
        Telemetry.event(TelemetryEvents.qrScanSuccess);
        Navigator.pop(context, value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_off_rounded,
                          color: Colors.white54, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        s.scanQrPermissionDenied,
                        style: YLText.body.copyWith(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(s.cancel,
                            style: const TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Top bar with close and flashlight
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Text(
                      s.scanQrTitle,
                      style: YLText.titleMedium.copyWith(color: Colors.white),
                    ),
                    const Spacer(),
                    IconButton(
                      icon:
                          const Icon(Icons.flash_on, color: Colors.white),
                      onPressed: () => _controller.toggleTorch(),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Scan area overlay hint
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.5),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

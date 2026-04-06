// Generates app icons for all platforms.
// Run: dart scripts/generate_icon.dart
// Then: dart run flutter_launcher_icons
//
// Outputs:
//   assets/icon.png         — iOS/Android (full-bleed square)
//   assets/icon_macos.png   — macOS (squircle + drop shadow on transparent bg)
//   assets/icon_desktop.png — Windows/Linux (rounded rect on transparent bg)

import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

void main() {
  const size = 1024;

  // ── 1. Base icon (iOS / Android) ─────────────────────────────────────────
  final base = _drawBaseIcon(size);
  _save(base, 'assets/icon.png');

  // ── 2. macOS icon (squircle + shadow on transparent) ─────────────────────
  final macos = _drawMacOSIcon(size);
  _save(macos, 'assets/icon_macos.png');

  // ── 3. Desktop icon (rounded rect on transparent, for Windows/Linux) ─────
  final desktop = _drawDesktopIcon(size);
  _save(desktop, 'assets/icon_desktop.png');

  // ── 4. DMG background ───────────────────────────────────────────────────
  final dmgBg = _drawDmgBackground(660, 400);
  _save(dmgBg, 'assets/dmg_background.png');

  print('\nAll icons generated. Now run: dart run flutter_launcher_icons');
}

// ═══════════════════════════════════════════════════════════════════════════
// Base icon — full-bleed indigo gradient + link symbol
// ═══════════════════════════════════════════════════════════════════════════

img.Image _drawBaseIcon(int size) {
  final image = img.Image(width: size, height: size);
  _fillGradient(image, 0, 0, size, size);
  _drawLinkSymbol(image, size);
  return image;
}

// ═══════════════════════════════════════════════════════════════════════════
// macOS icon — squircle (superellipse n≈5) with drop shadow
// Apple HIG: icon content ~824px in 1024px canvas, centered
// ═══════════════════════════════════════════════════════════════════════════

img.Image _drawMacOSIcon(int size) {
  final image = img.Image(width: size, height: size);
  // Transparent background
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      image.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }

  final cx = size ~/ 2;
  final cy = size ~/ 2;
  final radius = (size * 0.41).round(); // ~420px → ~840px squircle in 1024

  // Draw drop shadow (offset down 6px, blur ~16px)
  _drawSquircle(image, cx, cy + 6, radius, 5.0, (x, y, alpha) {
    final a = (alpha * 0.30 * 255).round(); // 30% black shadow
    if (a > 0) {
      // Blur approximation: soften edges
      final blur = 16;
      final edgeDist = alpha; // 0 at edge, 1 inside
      final blurAlpha = edgeDist < 0.05 ? (edgeDist / 0.05) : 1.0;
      final finalA = (a * blurAlpha).round().clamp(0, 255);
      if (finalA > 0) {
        _blendPixel(image, x, y, 0, 0, 0, finalA);
      }
    }
  });

  // Draw squircle with gradient fill
  final tempIcon = img.Image(width: size, height: size);
  _fillGradient(tempIcon, 0, 0, size, size);
  _drawLinkSymbol(tempIcon, size);

  _drawSquircle(image, cx, cy, radius, 5.0, (x, y, alpha) {
    if (alpha > 0.01) {
      final src = tempIcon.getPixel(x, y);
      final a = (alpha * 255).round().clamp(0, 255);
      _blendPixel(image, x, y, src.r.toInt(), src.g.toInt(), src.b.toInt(), a);
    }
  });

  // Subtle inner highlight (top edge, 8% white)
  _drawSquircle(image, cx, cy, radius, 5.0, (x, y, alpha) {
    if (alpha > 0.5) {
      final distFromTop = (y - (cy - radius)).toDouble();
      if (distFromTop < 3) {
        final highlight = ((3 - distFromTop) / 3 * 0.08 * 255).round();
        _blendPixel(image, x, y, 255, 255, 255, highlight);
      }
    }
  });

  return image;
}

// ═══════════════════════════════════════════════════════════════════════════
// Desktop icon — rounded rectangle for Windows/Linux
// ~860px rect in 1024 canvas, corner radius ~18% (modern Win11 style)
// ═══════════════════════════════════════════════════════════════════════════

img.Image _drawDesktopIcon(int size) {
  final image = img.Image(width: size, height: size);
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      image.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }

  final padding = (size * 0.08).round(); // 8% padding each side
  final rectSize = size - padding * 2;
  final cornerRadius = (rectSize * 0.18).round(); // 18% corner radius

  // Drop shadow
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final alpha = _roundedRectAlpha(
          x, y, padding, padding + 4, rectSize, rectSize, cornerRadius);
      if (alpha > 0.01) {
        final a = (alpha * 0.25 * 255).round().clamp(0, 255);
        _blendPixel(image, x, y, 0, 0, 0, a);
      }
    }
  }

  // Create temp icon for gradient + symbol
  final tempIcon = img.Image(width: size, height: size);
  _fillGradient(tempIcon, padding, padding, rectSize, rectSize);
  _drawLinkSymbol(tempIcon, size);

  // Draw rounded rectangle with icon content
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final alpha =
          _roundedRectAlpha(x, y, padding, padding, rectSize, rectSize, cornerRadius);
      if (alpha > 0.01) {
        final src = tempIcon.getPixel(x, y);
        final a = (alpha * 255).round().clamp(0, 255);
        _blendPixel(image, x, y, src.r.toInt(), src.g.toInt(), src.b.toInt(), a);
      }
    }
  }

  return image;
}

// ═══════════════════════════════════════════════════════════════════════════
// DMG background — subtle gradient with app name
// ═══════════════════════════════════════════════════════════════════════════

img.Image _drawDmgBackground(int w, int h) {
  final image = img.Image(width: w, height: h);
  // Light cool gray gradient
  for (int y = 0; y < h; y++) {
    final t = y / h;
    final r = _lerp(248, 240, t);
    final g = _lerp(249, 241, t);
    final b = _lerp(252, 245, t);
    for (int x = 0; x < w; x++) {
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  // Draw a subtle horizontal divider line at y=300 (above the drop area)
  for (int x = 60; x < w - 60; x++) {
    image.setPixelRgba(x, 310, 220, 222, 228, 255);
  }

  // Draw a small arrow from app icon area to Applications folder area
  final arrowY = 170;
  final arrowStartX = 260;
  final arrowEndX = 400;
  for (int x = arrowStartX; x <= arrowEndX; x++) {
    for (int dy = -1; dy <= 1; dy++) {
      image.setPixelRgba(x, arrowY + dy, 160, 163, 175, 180);
    }
  }
  // Arrow head
  for (int i = 0; i < 12; i++) {
    for (int dy = -i; dy <= i; dy++) {
      final px = arrowEndX - i;
      final py = arrowY + dy;
      if (px >= 0 && py >= 0 && py < h) {
        image.setPixelRgba(px, py, 160, 163, 175, 180);
      }
    }
  }

  return image;
}

// ═══════════════════════════════════════════════════════════════════════════
// Shared drawing helpers
// ═══════════════════════════════════════════════════════════════════════════

void _fillGradient(img.Image image, int ox, int oy, int w, int h) {
  // Indigo gradient: #6366F1 → #4F46E5
  for (int y = 0; y < h; y++) {
    final t = y / h;
    final r = _lerp(99, 79, t);
    final g = _lerp(102, 70, t);
    final b = _lerp(241, 229, t);
    for (int x = 0; x < w; x++) {
      final px = ox + x;
      final py = oy + y;
      if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
        image.setPixelRgba(px, py, r, g, b, 255);
      }
    }
  }
}

void _drawLinkSymbol(img.Image image, int size) {
  final cx = size ~/ 2;
  final cy = size ~/ 2;

  // Two interlocking chain rings
  _drawRing(image, cx - 120, cy, 200, 50);
  _drawRing(image, cx + 120, cy, 200, 50);

  // Subtle "Y" letter hint
  _drawThickLine(image, cx, cy - 180, cx - 100, cy - 320, 20, 80);
  _drawThickLine(image, cx, cy - 180, cx + 100, cy - 320, 20, 80);
  _drawThickLine(image, cx, cy - 180, cx, cy - 50, 20, 80);
}

void _drawRing(img.Image image, int cx, int cy, int radius, int thickness) {
  final rOuter = radius;
  final rInner = radius - thickness;
  for (int y = cy - rOuter; y <= cy + rOuter; y++) {
    for (int x = cx - rOuter; x <= cx + rOuter; x++) {
      if (x < 0 || x >= image.width || y < 0 || y >= image.height) continue;
      final dist = sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
      if (dist <= rOuter && dist >= rInner) {
        double alpha = 1.0;
        if (dist > rOuter - 2) alpha = (rOuter - dist) / 2;
        if (dist < rInner + 2) alpha = (dist - rInner) / 2;
        alpha = alpha.clamp(0.0, 1.0);
        if (alpha > 0.1) {
          final a = (alpha * 255).round();
          _blendPixel(image, x, y, 255, 255, 255, a);
        }
      }
    }
  }
}

void _drawThickLine(
    img.Image image, int x1, int y1, int x2, int y2, int thickness, int alpha) {
  final steps = max((x2 - x1).abs(), (y2 - y1).abs());
  if (steps == 0) return;
  final halfT = thickness ~/ 2;
  for (int i = 0; i <= steps; i++) {
    final t = i / steps;
    final lx = x1 + ((x2 - x1) * t).round();
    final ly = y1 + ((y2 - y1) * t).round();
    for (int dy = -halfT; dy <= halfT; dy++) {
      for (int dx = -halfT; dx <= halfT; dx++) {
        final px = lx + dx;
        final py = ly + dy;
        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          if (dx * dx + dy * dy <= halfT * halfT) {
            _blendPixel(image, px, py, 255, 255, 255, alpha);
          }
        }
      }
    }
  }
}

/// Superellipse (squircle) used by macOS icons.
/// Calls [paint] for each pixel inside with alpha 0..1 (anti-aliased edge).
void _drawSquircle(
  img.Image image,
  int cx,
  int cy,
  int radius,
  double exponent,
  void Function(int x, int y, double alpha) paint,
) {
  for (int y = cy - radius - 2; y <= cy + radius + 2; y++) {
    for (int x = cx - radius - 2; x <= cx + radius + 2; x++) {
      if (x < 0 || x >= image.width || y < 0 || y >= image.height) continue;
      final nx = (x - cx).abs() / radius.toDouble();
      final ny = (y - cy).abs() / radius.toDouble();
      final d = pow(nx, exponent) + pow(ny, exponent);
      if (d <= 1.05) {
        // Anti-aliased edge
        double alpha;
        if (d <= 0.95) {
          alpha = 1.0;
        } else {
          alpha = ((1.05 - d) / 0.10).clamp(0.0, 1.0);
        }
        paint(x, y, alpha);
      }
    }
  }
}

/// Rounded rectangle alpha for a given pixel. Returns 0..1.
double _roundedRectAlpha(
    int px, int py, int rx, int ry, int rw, int rh, int cornerR) {
  // Check if inside the rounded rect
  final left = rx;
  final top = ry;
  final right = rx + rw;
  final bottom = ry + rh;

  if (px < left - 1 || px > right + 1 || py < top - 1 || py > bottom + 1) {
    return 0.0;
  }

  // Inside the cross region (not in corner areas)
  if ((px >= left + cornerR && px <= right - cornerR) ||
      (py >= top + cornerR && py <= bottom - cornerR)) {
    if (px >= left && px <= right && py >= top && py <= bottom) {
      return 1.0;
    }
    // Anti-alias on straight edges
    double d = 0;
    if (px < left) d = (left - px).toDouble();
    if (px > right) d = (px - right).toDouble();
    if (py < top) d = max(d, (top - py).toDouble());
    if (py > bottom) d = max(d, (py - bottom).toDouble());
    return (1.0 - d).clamp(0.0, 1.0);
  }

  // In corner area — check distance to corner circle center
  int ccx, ccy;
  if (px < left + cornerR) {
    ccx = left + cornerR;
  } else {
    ccx = right - cornerR;
  }
  if (py < top + cornerR) {
    ccy = top + cornerR;
  } else {
    ccy = bottom - cornerR;
  }

  final dist = sqrt((px - ccx) * (px - ccx) + (py - ccy) * (py - ccy));
  if (dist <= cornerR - 1) return 1.0;
  if (dist >= cornerR + 1) return 0.0;
  return ((cornerR + 1 - dist) / 2.0).clamp(0.0, 1.0);
}

/// Alpha-blend a color onto the image at (x, y).
void _blendPixel(img.Image image, int x, int y, int r, int g, int b, int a) {
  if (x < 0 || x >= image.width || y < 0 || y >= image.height) return;
  if (a <= 0) return;
  if (a >= 255) {
    image.setPixelRgba(x, y, r, g, b, 255);
    return;
  }
  final dst = image.getPixel(x, y);
  final da = dst.a.toInt();
  final sa = a / 255.0;
  final outA = sa + (da / 255.0) * (1 - sa);
  if (outA <= 0) return;
  final outR = ((r * sa + dst.r.toInt() * (da / 255.0) * (1 - sa)) / outA).round();
  final outG = ((g * sa + dst.g.toInt() * (da / 255.0) * (1 - sa)) / outA).round();
  final outB = ((b * sa + dst.b.toInt() * (da / 255.0) * (1 - sa)) / outA).round();
  image.setPixelRgba(
      x, y, outR.clamp(0, 255), outG.clamp(0, 255), outB.clamp(0, 255), (outA * 255).round().clamp(0, 255));
}

int _lerp(int a, int b, double t) => (a + (b - a) * t).round();

void _save(img.Image image, String path) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(img.encodePng(image));
  print('Generated: $path (${image.width}x${image.height})');
}

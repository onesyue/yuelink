#!/usr/bin/env python3
"""Apply a squircle (superellipse) alpha mask to every desktop platform's
app icon, in place. The interior pixels — including the v1.0.13 indigo
gradient and the double-ring/V glyph — are preserved EXACTLY. Only the
corners become transparent so each platform renders the icon as a rounded
square ("圆润") instead of a hard square or, in the v1.0.13 Linux case,
a hard square with a black background bug.

Targets:
  1. macOS AppIconset PNGs   (7 sizes, in place)
  2. Linux source PNG        (assets/icon_desktop.png — replaces the buggy
                              v1.0.13 RGB-no-alpha file)
  3. Windows multi-frame ICO (windows/runner/resources/app_icon.ico,
                              7 sizes from 16 to 256)

iOS and Android are NOT touched:
  - iOS auto-applies its own squircle mask at the OS level.
  - Android adaptive icons (Android 8+) are masked per-launcher; touching
    assets/icon.png would break the adaptive foreground layer.

Usage:
    python3 scripts/round_appicon.py
    flutter clean && flutter build macos --debug

The script is idempotent — re-running it on already-rounded files is safe.
"""

from __future__ import annotations

import os
import sys
from PIL import Image

# Apple-style squircle: superellipse with exponent ≈ 5. Higher = closer to a
# perfect square; lower = closer to a circle. macOS Big Sur uses ~5.
N = 5.0

ICONSET = "macos/Runner/Assets.xcassets/AppIcon.appiconset"
LINUX_PNG = "assets/icon_desktop.png"
WINDOWS_ICO = "windows/runner/resources/app_icon.ico"
SOURCE_PNG = "assets/icon.png"  # v1.0.13 full-bleed indigo gradient + glyph
WINDOWS_ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]

# Wizard banner / DMG background output paths
WIZARD_LARGE_BMP = "windows/wizard_image.bmp"   # 164×314
WIZARD_SMALL_BMP = "windows/wizard_small.bmp"   # 55×58
DMG_BACKGROUND = "assets/dmg_background.png"    # 660×400


def apply_squircle_mask(img: Image.Image) -> Image.Image:
    """Return a copy of `img` with a superellipse alpha mask applied.

    Inner pixels are unchanged. Pixels at d > 1.0 (outside the squircle)
    become fully transparent. d ∈ [0.92, 1.0] gets an anti-aliased fade.
    """
    w, h = img.size
    img = img.convert("RGBA")
    pixels = img.load()

    cx, cy = (w - 1) / 2.0, (h - 1) / 2.0
    rx, ry = w / 2.0, h / 2.0

    for y in range(h):
        for x in range(w):
            nx = abs(x - cx) / rx
            ny = abs(y - cy) / ry
            d = nx ** N + ny ** N

            r, g, b, a = pixels[x, y]
            if d <= 0.92:
                continue  # safely inside, untouched
            elif d <= 1.0:
                fade = max(0.0, min(1.0, (1.0 - d) / 0.08))
                pixels[x, y] = (r, g, b, int(a * fade))
            else:
                pixels[x, y] = (r, g, b, 0)
    return img


def round_macos_appiconset() -> int:
    """Mask every PNG in the macOS AppIconset in place. Idempotent."""
    if not os.path.isdir(ICONSET):
        print(f"  ! {ICONSET} not found, skipping macOS")
        return 0

    pngs = sorted(f for f in os.listdir(ICONSET) if f.endswith(".png"))
    for f in pngs:
        path = os.path.join(ICONSET, f)
        img = Image.open(path)
        masked = apply_squircle_mask(img)
        masked.save(path)
        center = masked.getpixel((masked.size[0] // 2, masked.size[1] // 2))
        print(f"  ✓ {path}  center_rgb={center[:3]}")
    return len(pngs)


def round_linux_png() -> int:
    """Generate assets/icon_desktop.png as a squircle-masked copy of the
    v1.0.13 full-bleed icon.png. Replaces the buggy v1.0.13 file that had
    mode=RGB and solid-black corners.
    """
    if not os.path.exists(SOURCE_PNG):
        print(f"  ! {SOURCE_PNG} not found, skipping Linux")
        return 0

    img = Image.open(SOURCE_PNG).convert("RGBA")
    masked = apply_squircle_mask(img)
    masked.save(LINUX_PNG)
    corner = masked.getpixel((0, 0))
    center = masked.getpixel((masked.size[0] // 2, masked.size[1] // 2))
    print(
        f"  ✓ {LINUX_PNG}  corner_alpha={corner[3]} "
        f"center_rgb={center[:3]}"
    )
    return 1


def round_windows_ico() -> int:
    """Build a multi-frame Windows ICO from the squircle-masked source PNG,
    with frames at every standard size (16/24/32/48/64/128/256). PIL's ICO
    encoder takes the largest input image and downscales internally — we
    pre-mask before passing it in so every downscaled frame inherits the
    squircle alpha.
    """
    if not os.path.exists(SOURCE_PNG):
        print(f"  ! {SOURCE_PNG} not found, skipping Windows")
        return 0

    img = Image.open(SOURCE_PNG).convert("RGBA")
    masked = apply_squircle_mask(img)

    os.makedirs(os.path.dirname(WINDOWS_ICO), exist_ok=True)
    masked.save(
        WINDOWS_ICO,
        format="ICO",
        sizes=[(s, s) for s in WINDOWS_ICO_SIZES],
    )
    # Verify
    verify = Image.open(WINDOWS_ICO).convert("RGBA")
    print(
        f"  ✓ {WINDOWS_ICO}  frames={len(WINDOWS_ICO_SIZES)} "
        f"corner_alpha={verify.getpixel((0,0))[3]}"
    )
    return 1


# ─────────────────────────────────────────────────────────────────────────────
# Wizard banner + DMG background generation
#
# These derive their visuals from the REAL squircle YueLink icon (the one
# we just masked above), not from a hand-rolled "approximate" gradient. This
# guarantees brand consistency: the wizard banner shows the same logo and the
# same indigo color as the dock icon and the desktop YueLink.app.
# ─────────────────────────────────────────────────────────────────────────────


def get_brand_icon() -> Image.Image:
    """Return the squircle-masked YueLink icon (RGBA) at 1024 px. This is
    the single source of truth for all branded imagery."""
    img = Image.open(LINUX_PNG).convert("RGBA")
    return img


def get_brand_color() -> tuple[int, int, int]:
    """Sample the brand color from the center of the masked icon (where the
    indigo gradient is, away from the white glyph)."""
    icon = get_brand_icon()
    # Sample below the rings to get a clean indigo pixel
    w, h = icon.size
    px = icon.getpixel((w // 2, int(h * 0.82)))
    return (px[0], px[1], px[2])


def gradient_bg(w: int, h: int, top: tuple, bottom: tuple) -> Image.Image:
    """Vertical gradient background, opaque RGB."""
    img = Image.new("RGBA", (w, h), top + (255,))
    for y in range(h):
        t = y / max(1, h - 1)
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        for x in range(w):
            img.putpixel((x, y), (r, g, b, 255))
    return img


def make_wizard_large() -> int:
    """Inno Setup left wizard banner: 164×314.

    Layout:
      • Background: indigo gradient (top lighter, bottom darker)
        sampled from the real brand icon
      • Logo: real squircle YueLink icon centered horizontally,
        ~120 px wide, in the upper third
      • Bottom 40%: deeper indigo for visual weight (where Inno Setup
        will overlay the wizard's white text)
    """
    W, H = 164, 314
    SS = 4  # supersample for smooth gradient + crisp icon edges
    ssW, ssH = W * SS, H * SS

    # Sample brand color and derive a top-lighter / bottom-darker pair
    icon = get_brand_icon()
    base = get_brand_color()  # ≈ (89, 86, 235)
    # Lighter top ≈ blend with white at 35%
    top = tuple(int(c + (255 - c) * 0.35) for c in base)
    # Deeper bottom ≈ multiply by 0.55
    bot = tuple(int(c * 0.55) for c in base)

    bg = gradient_bg(ssW, ssH, top, bot)

    # Composite the real icon, large, centered horizontally, upper third
    icon_size = int(ssW * 0.78)
    icon_resized = icon.resize(
        (icon_size, icon_size), Image.Resampling.LANCZOS
    )
    icon_x = (ssW - icon_size) // 2
    icon_y = int(ssH * 0.18)
    bg.alpha_composite(icon_resized, (icon_x, icon_y))

    # Downsample
    final = bg.resize((W, H), Image.Resampling.LANCZOS)

    # BMP needs RGB (no alpha)
    flat = Image.new("RGB", (W, H), tuple(top))
    flat.paste(final.convert("RGB"))
    flat.save(WIZARD_LARGE_BMP, format="BMP")
    print(f"  ✓ {WIZARD_LARGE_BMP}  brand={base}")
    return 1


def make_wizard_small() -> int:
    """Inno Setup small icon: 55×58. Just the squircle logo on a white BG
    so it sits nicely next to the wizard's header text."""
    W, H = 55, 58
    SS = 4
    ssW, ssH = W * SS, H * SS

    icon = get_brand_icon()
    # Resize icon to fit width (height is slightly taller — center vertically)
    icon_resized = icon.resize((ssW, ssW), Image.Resampling.LANCZOS)

    # White background (BMP has no alpha — flatten anything transparent
    # against white so the wizard's white header is seamless)
    bg = Image.new("RGBA", (ssW, ssH), (255, 255, 255, 255))
    icon_y = (ssH - ssW) // 2
    bg.alpha_composite(icon_resized, (0, icon_y))

    final = bg.resize((W, H), Image.Resampling.LANCZOS)
    flat = Image.new("RGB", (W, H), (255, 255, 255))
    flat.paste(final.convert("RGB"))
    flat.save(WIZARD_SMALL_BMP, format="BMP")
    print(f"  ✓ {WIZARD_SMALL_BMP}")
    return 1


def make_dmg_background() -> int:
    """macOS DMG window background: 660×400.

    Same brand color sampled from the real icon. The icon coordinates in
    .github/workflows/build.yml expect:
      • YueLink.app at (180, 170)
      • Applications at (480, 170)
      • 修复无法打开.command at (330, 340)

    So we paint:
      • Diagonal indigo gradient (lighter at top-left, darker at bottom-right)
      • Drag-flow arrow at y=170 between x=240 and x=420
      • Soft horizontal divider at y=265 separating install zone from repair
    """
    W, H = 660, 400
    SS = 2
    ssW, ssH = W * SS, H * SS

    base = get_brand_color()  # ≈ (89, 86, 235)
    # Lighter top-left for the window background (don't make it too saturated;
    # the dock window itself is the focus, not the bg)
    tl = tuple(int(c + (255 - c) * 0.78) for c in base)
    br = tuple(int(c + (255 - c) * 0.62) for c in base)

    img = Image.new("RGBA", (ssW, ssH), tl + (255,))
    for y in range(ssH):
        for x in range(ssW):
            t = ((x / (ssW - 1)) * 0.45 + (y / (ssH - 1)) * 0.55)
            t = max(0.0, min(1.0, t))
            r = int(tl[0] + (br[0] - tl[0]) * t)
            g = int(tl[1] + (br[1] - tl[1]) * t)
            b = int(tl[2] + (br[2] - tl[2]) * t)
            img.putpixel((x, y), (r, g, b, 255))

    # Drag arrow at y=170, x 240→420 — uses the brand color at full saturation
    arrow_y = 170 * SS
    arrow_x1 = 240 * SS
    arrow_x2 = 420 * SS
    arrow_color = tuple(int(c * 0.7) for c in base)
    stroke = 6 * SS
    for y in range(arrow_y - stroke // 2, arrow_y + stroke // 2 + 1):
        for x in range(arrow_x1, arrow_x2 - stroke):
            img.putpixel((x, y), arrow_color + (180,))
    head = 18 * SS
    for i in range(head):
        for off in range(-stroke // 2, stroke // 2 + 1):
            # upper arrowhead diagonal
            yy1 = arrow_y - i + off
            xx1 = arrow_x2 - i
            if 0 <= xx1 < ssW and 0 <= yy1 < ssH:
                img.putpixel((xx1, yy1), arrow_color + (180,))
            # lower arrowhead diagonal
            yy2 = arrow_y + i + off
            if 0 <= xx1 < ssW and 0 <= yy2 < ssH:
                img.putpixel((xx1, yy2), arrow_color + (180,))

    # Soft divider at y=265
    div_y = 265 * SS
    div_x1 = 60 * SS
    div_x2 = (W - 60) * SS
    import math
    for x in range(div_x1, div_x2):
        progress = (x - div_x1) / (div_x2 - div_x1)
        a = int(math.sin(progress * math.pi) * 80)
        if a > 0:
            r, g, b, _ = img.getpixel((x, div_y))
            # Darken the band for the divider
            mix = lambda c: max(0, c - int(a * 0.3))
            img.putpixel((x, div_y), (mix(r), mix(g), mix(b), 255))
            img.putpixel((x, div_y + 1), (mix(r), mix(g), mix(b), 255))

    final = img.resize((W, H), Image.Resampling.LANCZOS)
    final.convert("RGB").save(DMG_BACKGROUND, format="PNG")
    print(f"  ✓ {DMG_BACKGROUND}  brand={base}")
    return 1


def main() -> int:
    print("Rounding desktop app icons (squircle mask, color-preserving)")
    print()

    print("→ macOS AppIconset (in place):")
    n_mac = round_macos_appiconset()
    print()

    print("→ Linux source PNG (regenerated from v1.0.13 icon.png):")
    n_lin = round_linux_png()
    print()

    print("→ Windows multi-frame ICO (regenerated):")
    n_win = round_windows_ico()
    print()

    print("→ Wizard banners (composited from real YueLink icon):")
    make_wizard_large()
    make_wizard_small()
    print()

    print("→ DMG background (brand color sampled from real icon):")
    make_dmg_background()
    print()

    print(
        f"Done. macOS frames: {n_mac}, Linux PNGs: {n_lin}, "
        f"Windows ICO: {n_win}"
    )
    print()
    print("iOS / Android NOT touched (system-level masking handles them).")
    print()
    print("Next: flutter clean && flutter build macos --debug")
    return 0


if __name__ == "__main__":
    sys.exit(main())

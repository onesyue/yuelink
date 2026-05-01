# Wintun bundling

Mihomo's TUN backend on Windows uses [WireGuard's Wintun driver](https://www.wintun.net/).
The DLL is **not** redistributed in this repository — see "Why not committed" below.

YueLink installs `wintun.dll` next to `yuelink.exe` at build time, **not** at
runtime. If the DLL is missing the desktop TUN diagnostic surfaces
`error_class = missing_driver` and the UI shows "Wintun 驱动缺失" — see
`lib/core/tun/desktop_tun_diagnostics.dart` (`_findWindowsWintunDll`) for the
candidate paths.

## Layout

```
windows/third_party/wintun/
  ├─ README.md                 (this file)
  ├─ amd64/wintun.dll          (downloaded by CI; gitignored)
  ├─ arm64/wintun.dll          (downloaded by CI; gitignored)
  └─ wintun.sha256             (committed — pinned upstream hashes)
```

`wintun.sha256` is the verification trip-wire. CI fetches the upstream
zip, extracts both architectures, then `sha256sum --check`s against this
file. Any drift fails the build before `windows-x64-Release` is signed.

## Why not committed

1. The DLL is upstream-licensed (GPL-2). Vendoring it in a public repo
   is allowed but invites stale-binary drift between repo and upstream.
2. CI-time download forces every release to verify hashes, which is
   what we want as a release-gate signal anyway.
3. The bundled binary differs by architecture (x64 vs arm64). Carrying
   both fattens the working tree without a clear win — the install
   step picks the right one based on `CMAKE_VS_PLATFORM_NAME`.

## How CI gets the DLL

The Windows leg of `.github/workflows/build.yml` runs
`scripts/check_windows_wintun_bundle.ps1 -Download` before
`flutter build windows`:

```yaml
- name: Bundle Wintun (Windows)
  if: matrix.platform == 'windows'
  shell: pwsh
  run: ./scripts/check_windows_wintun_bundle.ps1 -Download
```

That script:

1. Downloads `https://www.wintun.net/builds/wintun-0.14.1.zip`.
2. Verifies `sha256` against `windows/third_party/wintun/wintun.sha256`.
3. Extracts `bin/amd64/wintun.dll` → `windows/third_party/wintun/amd64/`.
4. Extracts `bin/arm64/wintun.dll` → `windows/third_party/wintun/arm64/`.
5. Re-verifies the unpacked DLLs against the same hash file.

After the build the same script runs in `-Verify` mode against the
final bundle so missing DLLs fail the release-gate, not the user's
first launch.

## Local developer flow

If you want to build a Windows binary locally:

```pwsh
# from repo root, on a Windows host or via WSL with pwsh
./scripts/check_windows_wintun_bundle.ps1 -Download
flutter build windows --release
./scripts/check_windows_wintun_bundle.ps1 -Verify -BundleDir build/windows/x64/runner/Release
```

Or on a non-Windows host you can verify a pre-built bundle:

```bash
bash scripts/check_windows_wintun_bundle.sh --verify path/to/extracted/release
```

## Updating the upstream version

When upstream cuts a new Wintun release:

1. Download both archives, compute `sha256sum`.
2. Replace the four entries in `wintun.sha256` (zip + amd64 + arm64,
   plus a `WINTUN_VERSION` line for traceability).
3. Update the URL in `scripts/check_windows_wintun_bundle.ps1`
   (single `$WINTUN_URL` variable at top).
4. Run a Windows release on a `pre` tag. If the binary launches and
   `desktop_tun_diagnostics` reports `driver_present=true`, ship.

Do **not** update the hashes from a downloaded copy without checking
the upstream `signify` signature. Wintun is signed; verify before
trusting.

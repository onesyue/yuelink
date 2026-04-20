# Dependency Upgrade Plan — win32 5 → 6

Status: **blocked**, pending upstream releases. Plan captured here so
future upgrade attempts don't re-derive the constraint graph.

Last verified: 2026-04-20 against pubspec.lock, `flutter pub deps
--style=compact`, and pub.dev changelog pages.

## TL;DR

- Five of our dependencies (direct + transitive) still pin `win32 ^5`.
- `flutter_secure_storage 10`, `package_info_plus 10`, `wakelock_plus
  1.6`, and `win32_registry 3` are ready to move to `win32 ^6`.
- **Two packages block the combined bump**: `file_picker 11.0.2`
  (latest, still on `win32 ^5.9.0`) and `launch_at_startup 0.5.1`
  (unreleased for 12 months, constrains `win32_registry ^2.0.0`).
- Before we can safely flip to `flutter_secure_storage 10`, Android
  users need `SecureStorageMigration.backupToShadow()` to have run in a
  prior release — otherwise their auth token / subscribe URL / mihomo
  API secret silently vanish on upgrade (fss 10 changes the Android
  cipher out from under the encrypted SharedPreferences blob).

## Current constraint graph

Snapshot from `flutter pub deps --style=compact` on 2026-04-20:

| Package (direct) | Current | On win32 | Status |
|---|---|---|---|
| `file_picker` | 11.0.2 | `^5.9.0` | **BLOCKER** — latest is 11.0.2, no win32-6 release published |
| `flutter_secure_storage` | 9.2.4 | `^5.0.0` (via `_windows 3.1.2`) | available at 10.0.0 but Android migration risk |
| `package_info_plus` | 9.0.1 | `^5.x` | available at 10.0.0, API compatible |
| `wakelock_plus` | 1.5.2 | `^5.x` | available at 1.6.0 on win32 `^6` |
| `launch_at_startup` | 0.5.1 | indirect via `win32_registry ^2` | **BLOCKER** — 12 months stale, no win32-6 release |
| `win32_registry` (transitive) | 2.1.0 | `^5.x` | available at 3.0.3 on win32 `^6` (needs launch_at_startup to relax its constraint) |

Empirical: raising only `package_info_plus: ^10.0.0` fails immediately
with:

```
file_picker ^11.0.2 requires win32 ^5.9.0 which is incompatible
with package_info_plus >=10.0.0 requires win32 ^6.0.0
```

This is why piecewise upgrades don't work — every win32-touching
package advances together or none do.

## Why we care about fss 10

Three motivations:

1. **Discontinued transitive dependency**: `js 0.6.7` (discontinued on
   pub.dev) is pulled in via `flutter_secure_storage_web 1.2.1`. fss 10
   replaces it with `package:web`.
2. **WASM compatibility**: fss 10 works under WebAssembly; fss 9
   doesn't. Not critical for YueLink today but future-relevant.
3. **Android security defaults**: fss 10 ships new cipher defaults
   (`RSA_ECB_OAEPwithSHA_256andMGF1Padding` + `AES_GCM_NoPadding`) and
   deprecates Jetpack Crypto `encryptedSharedPreferences: true`, which
   is what we currently pass.

## Why fss 10 is not a drop-in for us

The **Android** backend cipher change means existing on-device blobs
become unreadable after the upgrade. In practice: a logged-in user who
updates the app lands on the login screen on first launch, with no
explanation, because every key we store via `flutter_secure_storage`
reads back as `null`:

- `yue_auth_token`
- `yue_subscribe_url`
- `yue_user_profile` (cached)
- `yue_profile_cached_at`
- `yue_api_host`
- `mihomo_api_secret`
- `sub_url_<profileId>` (one per subscription)

**Windows** also changes backend (Credential Locker → file store) in
fss 10 and has the same "read returns null" failure mode.

**macOS** is unaffected — we don't use flutter_secure_storage on macOS
(see `_MacEncryptedStore` in `secure_storage_service.dart`).

**iOS** Keychain is API-compatible; low migration risk.

**Linux** moves `flutter_secure_storage_linux` 1.x → 3.x (two majors);
needs verification but affects a negligible user share.

## The migration bridge

`SecureStorageMigration` (lib/core/storage/secure_storage_migration.dart,
shipped but not wired into startup as of commit TBD) implements the
backup half:

- On the last fss-9 release, call `backupToShadow(profileIds: [...])`
  at app start. This reads every known key out of fss 9 and writes a
  JSON shadow under Application Support. Idempotent.
- On the first fss-10 release, read the shadow, write values through
  the new fss 10 backend, and `clearShadow()`. (Restore half — not
  implemented yet; wire-up is its own PR once we have fss 10 in the
  resolve graph.)

Shadow file is currently **plaintext**. Before wiring into production
startup, swap the file backend for the AES-256-GCM envelope
`_MacEncryptedStore` already uses (machine-UUID-bound, HKDF-derived
key). Test plumbing in `secure_storage_migration_test.dart` will not
change — the class takes injected read/write/delete callbacks.

## Proposed order once blockers clear

1. **Ship `SecureStorageMigration` wired into startup**, with the
   encrypted-shadow backend in place. Release N.
   - Validate: shadow file appears under Application Support after
     first launch post-upgrade, count matches `knownStaticKeys` ∪
     profile count.
2. **Wait ≥ 1 minor release** so the backup has time to run on ≥ 95%
   of the install base. This is the single biggest "don't break users"
   lever we have.
3. **Wait for upstream to unblock**:
   - `file_picker` publishes a release depending on `win32: ^6` (or
     we swap to `file_selector` from the Flutter team).
   - `launch_at_startup` publishes ≥ 0.6 depending on
     `win32_registry: ^3` (or we fork the ~200-line registry poke).
4. **Combined bump in one PR** (release N+k):
   - `flutter_secure_storage: ^10.0.0`
   - `package_info_plus: ^10.0.0`
   - `wakelock_plus: ^1.6.0`
   - `file_picker: ^12.x` (or swap)
   - `launch_at_startup: ^0.6.x` (or fork)
   - `win32_registry: ^3.0.3`
   - Implement `SecureStorageMigration.restoreFromShadow()` and wire it
     into startup ahead of the first read through `AuthTokenService` /
     `SecureStorageService`.
5. **Validation checklist for the combined PR**:
   - `flutter pub get` resolves.
   - `flutter analyze` clean (modulo the pre-existing 14 info in
     frozen/dirty areas).
   - `flutter test` green.
   - Windows desktop: cold-start smoke with a pre-upgrade install —
     user stays logged in, subscription list intact, start-on-boot
     toggle still works.
   - Android: cold-start smoke with a pre-upgrade install — all 6 known
     keys plus per-profile `sub_url_*` keys recovered.
   - iOS: smoke check (should be a no-op, but verify).
   - Linux: smoke check; if libsecret behavior differs, document.
6. **Cleanup release** ≥ 2 minors after the bump: call `clearShadow()`
   unconditionally on startup, then remove `SecureStorageMigration`
   entirely.

## Non-goals

- **Do not** preempt this plan by raising a single win32-touching
  package — every attempt will bounce off the constraint graph.
- **Do not** skip the shadow precondition. "Android users silently
  logged out after an update" is a much worse bug than a delayed
  dependency bump. `flutter_secure_storage` release notes say nothing
  about providing migration; we own this.
- **Do not** drop macOS-specific `_MacEncryptedStore` in the same PR —
  it's a separate backend, not a flutter_secure_storage consumer, and
  rolling it in would expand the blast radius for no benefit.

## See also

- `lib/core/storage/secure_storage_migration.dart` — backup half of the
  bridge, test-covered.
- `test/core/storage/secure_storage_migration_test.dart` — 6 cases
  locking down idempotency, missing-value handling, failure accounting,
  and secret non-leakage into `event.log`.
- `lib/core/storage/secure_storage_service.dart` — current fss 9
  wrapper; will become the destination of `restoreFromShadow()` in the
  combined PR.
- `lib/core/storage/auth_token_service.dart` — declares 5 of the 6
  static keys listed in `knownStaticKeys`.

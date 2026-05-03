# Tech debt registry

Last updated 2026-05-03 (post S0-S6 code-quality closeout).

The point of this file: stop relying on memory to know what was deliberately
deferred and why. Each entry says **what** the debt is, **why we are not
touching it now**, and **what would re-open it**. Anything not in this file
is fair game for opportunistic cleanup.

## 1. Risk Debt - Do Not Touch In RC

### CoreManager 8-step startup
- **Where:** `lib/core/kernel/core_manager.dart`
- **Why not:** Single chokepoint every connect path runs through. Already
  covered by startup/recovery tests and StartupReport error codes E002-E009.
- **Reopen when:** A new platform forces a 9th startup step, or StartupReport
  codes stop matching real failures.

### service_manager.dart install / update / uninstall scripts
- **Where:** `lib/core/service/service_manager.dart`
- **Why not:** Privileged `osascript` / `pkexec` / UAC script execution. S2/S6
  only added read-only probes and tests; install script bodies remain out of
  scope.
- **Reopen when:** A platform elevation flow changes, or a security issue
  requires a targeted script patch.

### Node treatment overhaul
- **Where:** `docs/sre/p5_active_probe_design.md`,
  `docs/sre/p7_node_state_machine.md`
- **Why not:** Operational reliability project, not code-quality RC cleanup.
- **Reopen when:** Reliability RC explicitly starts node governance work.

## 2. Closed In This Closeout

- **S1b connection repair widget split:** `connection_repair_page.dart` now
  keeps page/action orchestration only; helper widgets live under
  `lib/modules/settings/connection_repair/widgets/`.
- **S2 platform coverage limit:** `ServicePlatformProbe` now covers macOS,
  Linux, and Windows `isInstalled` state combinations in
  `test/services/service_manager_test.dart`.
- **S4 ConfigTemplate split:** `config_template.dart` delegates to transformer
  files under `lib/core/kernel/config/`; golden output remains locked.
- **S6 main bootstrap split:** startup storage, runtime init, and
  single-instance guard moved to `lib/app/bootstrap/`.
- **Riverpod legacy comment cleanup:** old `.notifier.state` / legacy import
  comments in code were removed.
- **Pending order page-1 workaround:** `StoreRepository.fetchPendingOrderForPlan`
  now does bounded pagination so purchase reuse is no longer first-page-only.
- **connection_repair widget smoke tests:** moved widgets are covered by
  `test/modules/connection_repair_widgets_test.dart`.

## 3. Remaining Form Debt

### Large page files
- **Files:** `nodes_page.dart`, `profiles_page.dart`, `dashboard_page.dart`
- **Why not:** Single-page UI breadth, not correctness risk. Split only when
  touching those pages for feature work.
- **Reopen when:** A widget becomes shared or a page change becomes hard to
  review because unrelated UI sections sit in the same diff.

## 4. External / Operational Risks

### Single-host backend
- **Services on one VM:** YueOps web, checkin-api, telemetry, fallback XBoard
  origin probe.
- **Risk:** Provider outage takes panel + telemetry down together.
- **Why not:** Ops architecture decision, not a client-code cleanup.

### XBoard dedicated pending-order API absent
- **Status:** Client now has bounded pagination fallback through
  `fetchPendingOrderForPlan`.
- **Why still tracked:** A server-side `getPendingOrder(planId)` endpoint would
  be cheaper and exact, but requires XBoard plugin/backend work.
- **Reopen when:** Users with long order histories still recreate pending
  orders past the bounded scan depth.

### iOS Pods dependency chain
- **Surface:** SDWebImage / DKImagePickerController / DKPhotoGallery /
  SwiftyGif image stack.
- **Why not:** Pods are not committed. Removing requires tracing the actual
  image feature and replacing or deleting it.
- **Reopen when:** iOS binary size or a dependency CVE becomes a release
  blocker.

## 5. Explicitly Not Debt

- **flutter_riverpod 3.x migration:** Complete; no
  `flutter_riverpod/legacy.dart` import remains in `lib/` or `test/`.
- **Bug 5 payment empty URL:** Fixed with repository decline + poll fail-close;
  regression coverage exists in `purchase_notifier_test.dart`.
- **Recovery manager notifier types:** Fixed with regression coverage in
  `recovery_manager_test.dart`.

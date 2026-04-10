# YueLink Design Specification
> Implementation-ready. All decisions are final unless explicitly revised.

---

## 1. Design Direction

**Goal**: A minimal, professional, cross-platform proxy tool. Not a Clash skin, not an airport panel.

**Anti-patterns to avoid**:
- Gradient buttons, glow effects, neon colors
- Card-in-card nesting more than two levels deep
- Colored icon-in-square badges (airport circle aesthetic)
- Full-screen empty state illustrations
- Pill buttons that are larger than 36px tall

**Allowed visual vocabulary**:
- Zinc-based neutral palette
- Indigo-600 as the single accent
- Semantic colors only for status (green=connected, amber=warning, red=error)
- Thin borders (0.5–1px) instead of shadows
- Restrained corners (4–12px, never pill-shaped except toggle chip)

---

## 2. Color System

All colors defined in `lib/theme.dart → YLColors`.

### Neutrals (zinc)
| Token         | Hex       | Use                          |
|---------------|-----------|------------------------------|
| `zinc50`      | #FAFAFA   | Light bg                     |
| `zinc100`     | #F4F4F5   | Light input fill             |
| `zinc200`     | #E4E4E7   | Light border, divider        |
| `zinc300`     | #D4D4D8   | Light disabled               |
| `zinc400`     | #A1A1AA   | Light secondary text         |
| `zinc500`     | #71717A   | Both: tertiary text, icons   |
| `zinc600`     | #52525B   | Dark disabled                |
| `zinc700`     | #3F3F46   | Dark border                  |
| `zinc800`     | #27272A   | Dark surface (cards)         |
| `zinc900`     | #18181B   | Dark bg                      |
| `zinc950`     | #0F0F10   | Dark deep bg (rare)          |

### Semantic
| Token         | Hex       | Use                          |
|---------------|-----------|------------------------------|
| `primary`     | #4F46E5   | Indigo-600, selected states  |
| `primaryLight`| #EEF2FF   | Primary bg tint (light only) |
| `connected`   | #16A34A   | Running status               |
| `connecting`  | #D97706   | Transitioning status         |
| `disconnected`| #71717A   | Stopped status               |
| `error`       | #DC2626   | Error, timeout               |
| `errorLight`  | #FEF2F2   | Error bg tint (light only)   |

### Surface rules
| Context        | Light      | Dark          |
|----------------|------------|---------------|
| Page bg        | zinc50     | zinc900       |
| Card / surface | white      | zinc800       |
| Input fill     | zinc100    | zinc700       |
| Border         | zinc200    | zinc700       |
| Divider        | #0E000000  | #18FFFFFF     |

---

## 3. Typography Scale

All styles defined in `lib/theme.dart → YLText`.

| Token         | Size | Weight | LetterSpacing | Use                              |
|---------------|------|--------|---------------|----------------------------------|
| `display`     | 28px | 700    | −0.8          | Traffic numbers, big status      |
| `titleLarge`  | 17px | 600    | −0.3          | Page title, AppBar               |
| `titleMedium` | 15px | 600    | −0.2          | Card header, group name          |
| `body`        | 13px | 400    | 0             | Body text, list primary          |
| `label`       | 12px | 500    | 0             | Chips, form labels               |
| `caption`     | 11px | 400    | 0             | Section headers, timestamps      |
| `mono`        | 13px | 500    | 0             | Port numbers, IPs                |

### Numeric typography rule (tabular figures)

**Always use `FontFeature.tabularFigures()`** for any value that changes over time or must align in columns:

| Value type      | Style token  | Size  | Weight | Tabular |
|-----------------|-------------|-------|--------|---------|
| Latency (ms)    | custom       | 10px  | 600    | yes     |
| Traffic speed   | `display`    | 13px  | 600    | yes     |
| Traffic totals  | custom       | 11px  | 500    | yes     |
| Connection count| `mono`       | 13px  | 600    | yes     |
| Uptime timer    | custom       | 11px  | 400    | yes     |
| Port numbers    | `mono`       | 13px  | 500    | yes     |
| IP addresses    | `mono`       | 13px  | 500    | yes     |

Example:
```dart
Text('${delay}ms', style: const TextStyle(
  fontSize: 10, fontWeight: FontWeight.w600,
  fontFeatures: [FontFeature.tabularFigures()],
  color: _delayColor(delay),
))
```

---

## 4. Spacing & Radius

### Spacing tokens (`YLSpacing`)
```
xs=4  sm=8  md=12  lg=16  xl=24  xxl=32
```

### Radius tokens (`YLRadius`)
```
sm=4  md=6  lg=8  xl=12
```

### Usage rules
- Cards: `YLRadius.lg` (8px)
- Node grid cells: 7px (between `md` and `lg`, use literal)
- Type chips / delay badges: `YLRadius.sm` (4px)
- Toggle pill: 20px (hardcoded, only exception)
- Modal dialogs: `YLRadius.xl` (12px)

---

## 5. Density Rules

### Desktop (width > 640px)
- `VisualDensity.compact` on ThemeData
- `ListTile` height: 40px (via `dense: true` + `minVerticalPadding: 0`)
- Section label top padding: 16px, bottom: 6px
- Card internal padding: `EdgeInsets.symmetric(horizontal: 12, vertical: 10)`
- Stat card padding: `EdgeInsets.symmetric(horizontal: 12, vertical: 10)`
- Dividers: 0.5px thickness
- Button height: 34px minimum
- Grid node cards: `childAspectRatio: 2.4`, min cell width 130px

### Mobile (width ≤ 640px)
- `VisualDensity.standard`
- `ListTile` height: Material default (48px)
- Section label top padding: 20px, bottom: 8px
- Card internal padding: `EdgeInsets.symmetric(horizontal: 16, vertical: 12)`
- Stat card padding: `EdgeInsets.symmetric(horizontal: 16, vertical: 12)`
- Dividers: 1px thickness
- Button height: 44px minimum
- Grid node cards: `childAspectRatio: 2.2`, min cell width 120px

---

## 6. Page-Specific Width Strategies

### Home
- **Strategy**: Constrained center column
- Max content width: 800px
- Padding: 16px horizontal (desktop), 12px (mobile)
- Stats row: always 3-column horizontal layout on desktop; 3-column on mobile too if width > 360px, else 1-column stack

### Nodes (proxy groups + node grid)
- **Strategy**: Full bleed
- Groups list: full width
- Node grid cells: `max(2, (containerWidth / 130).floor())` columns
- No max-width constraint — uses all available space

### Connection (active connections table)
- **Strategy**: Full bleed with column hiding
- Width > 800px: show all 7 columns (target, protocol, rule, process, ↑, ↓, duration)
- Width 500–800px: hide upload column
- Width < 500px: show target + rule + ↓ only (3 columns)

### Configurations (profile/subscription management)
- **Strategy**: Constrained center column
- Max content width: 640px
- Centered with auto side margins on desktop

### Settings
- **Strategy**: Constrained center column
- Max content width: 560px
- Centered with auto side margins on desktop

---

## 7. Page Responsibility Boundaries

### Home — Operational status center
**Shows**: Connection toggle, live speed (up/down), memory usage, today's traffic total, exit IP, routing mode selector, uptime, active profile name.
**Does not show**: Active connection list, node grid, subscription details, logs.
**Primary action**: Connect / Disconnect toggle.

### Nodes — Proxy group and node management
**Shows**: All proxy groups (ordered by GLOBAL group), each group expanded with its node grid, delay values, type chip, test-all button. Routing mode segmented control at top.
**Does not show**: Live traffic, connection status banner, exit IP.
**Primary action**: Select a node, trigger delay test.

### Connection — Session diagnostics
**Shows**: Active connection table (target, protocol, process, rule, bytes, duration), session-level cumulative stats (total ↑/↓, connection count), close-all button, search/filter.
**Does not show**: Exit IP (that's Home), connection toggle, node grid.
**Not a duplicate of Home**: Home shows live speeds and uptime. Connection shows the per-connection table.
**Primary action**: Inspect / close individual connections.

### Configurations — Subscription management
**Shows**: Profile list with usage bar, expiry badge, update timestamp, active indicator. Add / edit / delete actions. Import from file or clipboard.
**Does not show**: Proxy settings, app behavior settings.
**Primary action**: Add/update subscription, set active profile.

### Settings — App behavior configuration
**Shows** (5 sections):
1. **General** — Auto-connect, launch at startup, theme, language
2. **Proxy** — Connection mode (TUN/system proxy), system proxy on connect, routing default
3. **Subscription & Sync** — Auto-update interval, update all now, Sub-Store URL
4. **Core** — Log level, config overwrite, geo resources
5. **Diagnostics** — DNS query, running config viewer, flush DNS/Fake-IP cache, split tunneling (Android), logs

---

## 8. UI State System

### 8a. Global Connection States

Maps to `CoreStatus` enum in `core_provider.dart`:

| State        | `CoreStatus`     | Status dot color    | Toggle label  | Body content           |
|--------------|-----------------|---------------------|---------------|------------------------|
| Stopped      | `.stopped`       | `zinc400`/`zinc500` | Connect       | `_DisconnectedBody`    |
| Starting     | `.starting`      | `connecting` amber  | spinner       | centered spinner       |
| Running      | `.running`       | `connected` green   | Disconnect    | stats + chart          |
| Stopping     | `.stopping`      | `connecting` amber  | spinner       | centered spinner       |

Pages that gate on connection (Nodes, Connection):
- Display `YLEmptyState` with `Icons.power_off_outlined` and message when not running
- Do not show a spinner for transitioning states on these pages (only Home does)

### 8b. Node States

Per proxy group:
| State     | When                              | UI treatment                     |
|-----------|-----------------------------------|----------------------------------|
| Unloaded  | `proxyGroupsProvider` is `[]`     | shimmer or spinner in group card |
| Loaded    | list populated                    | render grid                      |

Per node delay:
| State    | Condition               | Display           | Color              |
|----------|-------------------------|-------------------|--------------------|
| Untested | not in `delayResults`   | speed icon (12px) | `zinc400`          |
| Testing  | in `delayTesting` set   | 10×10 spinner     | —                  |
| Fast     | 1–99ms                  | `${d}ms`          | `#34C759` green    |
| Medium   | 100–299ms               | `${d}ms`          | amber `#D97706`    |
| Slow     | 300ms+                  | `${d}ms`          | red `#DC2626`      |
| Timeout  | `d <= 0`                | `timeout`         | red `#DC2626`      |

### 8c. Configuration States

Per profile card:
| State          | Condition                            | Badge / indicator               |
|----------------|--------------------------------------|---------------------------------|
| Active         | `id == activeProfileId`              | left border `primary`, checkmark|
| Fresh          | `updatedAt` within 24h               | no badge                        |
| Needs update   | `updatedAt` older than interval      | amber "Needs update" chip       |
| Updating       | `isUpdating == true`                 | inline spinner                  |
| Update success | just updated (transient 3s)          | green "Updated" chip            |
| Update failed  | `lastError != null`                  | red "Failed" chip               |
| Expiring soon  | `daysRemaining <= 7`                 | amber `${days}d left` chip      |
| Expired        | `isExpired == true`                  | red "Expired" chip              |
| No config file | `ProfileService.loadConfig` == null  | amber "No file" chip            |

### 8d. Diagnostics States (Settings → Diagnostics section)

DNS Query tool:
| State     | Condition          | UI                                    |
|-----------|--------------------|---------------------------------------|
| Idle      | initial            | empty input, Query button enabled     |
| Querying  | in-flight          | button disabled, inline spinner       |
| Result    | response received  | result list below input               |
| Error     | exception caught   | red error text below input            |

Log level / running config: stateless pickers — no special state needed.
Geo resources:
| State     | UI                                    |
|-----------|---------------------------------------|
| Unknown   | "—" size display                      |
| Present   | file size                             |
| Missing   | "Not found" in red caption            |
| Updating  | progress indicator per file           |

---

## 9. Component System

### 9a. Foundation Components (in `theme.dart`)

Already implemented:
- `YLColors` — color tokens
- `YLText` — typography scale
- `YLSpacing` / `YLRadius` — spacing tokens
- `YLStatusDot(color, size)` — 7px status indicator circle
- `YLSectionLabel(text)` — uppercase 11px section header
- `YLInfoRow(label, value, trailing, onTap, enabled)` — label-left / value-right row
- `YLSettingsRow(title, description, trailing, onTap, enabled)` — settings row with optional subtitle
- `YLSurface(child, margin, padding)` — bordered card container
- `YLChip(label, color)` — colored mini chip with tinted bg

### 9b. Business Components (to be added to `theme.dart`)

#### `YLEmptyState`
```
icon: IconData
message: String
```
Usage: All pages when disconnected or data unavailable.
Layout: Column centered, icon 36px zinc400/0.4 opacity, 12px gap, caption text zinc500.

#### `YLDelayBadge`
```
delay: int?     // null = untested
testing: bool
```
Usage: Node card bottom-left.
Rules: See §8b delay color table. Always tabular figures.

#### `YLNodeCard`
```
name: String
isSelected: bool
delay: int?
isTesting: bool
onSelect: VoidCallback
onTest: VoidCallback
```
Usage: `GridView` inside each proxy group.
Layout: AnimatedContainer, name top-left (max 2 lines, 11px), delay badge bottom-left.
Selected: `primary` border 1.5px, bg `primary.withValues(0.07)`.
Unselected: border 0.5px zinc200/zinc700.
Radius: 7px.

#### `YLGroupCard`
```
group: ProxyGroup
delays: Map<String, int>
testing: Set<String>
onSelectNode: (String) void
onTestGroup: VoidCallback
```
Usage: Nodes page list items.
Layout: Column — group header row + node grid + count footer.
Header: icon 14px + name `titleMedium` + type chip + `now` text 11px + spacer + test-all button.

#### `YLProfileCard`
```
profile: Profile
isActive: bool
isUpdating: bool
onActivate: VoidCallback
onUpdate: VoidCallback
onEdit: VoidCallback
onDelete: VoidCallback
```
Usage: Configurations page list.
Layout: Row — left active indicator (4px bar or none) + body (name, usage bar, metadata row) + trailing actions.

#### `YLStatCard`
```
icon: IconData
iconColor: Color
label: String
value: String
onTap: VoidCallback?
trailing: Widget?
```
Usage: Home page stats row.
Layout: Column — label row (icon + text + trailing) + value text.
Numbers use tabular figures.

#### `YLConnectionRow`
```
connection: ActiveConnection
onClose: VoidCallback
onTap: VoidCallback
```
Usage: Connection page table.
Columns by width: see §6 Connection width strategy.

---

## 10. Navigation Structure

```
MainShell
├── Home          (tab 0, Icons.home_outlined)
├── Nodes         (tab 1, Icons.router_outlined)
├── Connection    (tab 2, Icons.wifi_tethering_outlined)
├── Configurations(tab 3, Icons.folder_outlined)
└── Settings      (tab 4, Icons.settings_outlined)
```

Desktop: `NavigationRail`, width 64px, `labelType: all`.
Mobile: `NavigationBar`, height 60px, `onlyShowSelected` labels.
Both use theme-defined styles (no inline overrides).

---

## 11. Settings Page Section Map

```
Settings
├── General
│   ├── Auto-connect on startup        [Switch]
│   ├── Launch at startup (desktop)    [Switch]
│   ├── Theme                          [Radio: System/Light/Dark]
│   └── Language                       [Radio: 中文/English]
├── Proxy
│   ├── Connection mode                [Dropdown: TUN/System Proxy]
│   ├── Set system proxy on connect    [Switch, desktop only]
│   └── Default routing mode          [Segmented: Rule/Global/Direct]
├── Subscription & Sync
│   ├── Auto-update interval           [Dropdown]
│   ├── Update all now                 [Action row]
│   ├── Sub-Store server URL           [TextField row]
├── Core
│   ├── Log level                      [Dropdown]
│   └── Config overwrite               [Nav row → OverwritePage]
└── Diagnostics
    ├── Logs                           [Nav row → LogPage]
    ├── DNS query                      [Nav row → DnsQueryPage]
    ├── Running config                 [Nav row → RunningConfigPage]
    ├── Geo resources                  [Inline section]
    ├── Flush DNS cache                [Action row]
    ├── Flush Fake-IP cache            [Action row]
    └── Split tunneling (Android only) [Nav row]
```

---

## 12. Inter-page Navigation

| From          | Action                     | Target                  |
|---------------|----------------------------|-------------------------|
| Home stats    | Tap node card              | Nodes tab (switchTab)   |
| Home          | No profile → hint          | Configurations tab      |
| Nodes         | (self-contained)           | —                       |
| Connection    | (self-contained)           | —                       |
| Configurations| Tap profile                | activates profile       |
| Settings/Core | Config overwrite           | push OverwritePage      |
| Settings/Diag | Logs                       | push LogPage            |
| Settings/Diag | DNS query                  | push DnsQueryPage       |
| Settings/Diag | Running config             | push RunningConfigPage  |

Deep links (`clash://install-config?url=...`) open Configurations tab.

---

## 13. Implementation Priority

1. **`theme.dart`** — Add `YLEmptyState`, `YLDelayBadge`, `YLNodeCard`, `YLGroupCard`, `YLStatCard`, `YLProfileCard` business components.
2. **`pages/nodes_page.dart`** — Full implementation replacing proxy_page.dart proxy. Use `YLGroupCard`, `YLNodeCard`.
3. **`pages/settings_page.dart`** — Restructure into 5 sections using `YLSectionLabel`, `YLSettingsRow`, `YLInfoRow`. Add Diagnostics section with Logs nav row.
4. **`pages/home_page.dart`** — Use `YLStatCard`. Constrain to 800px max-width on desktop.
5. **`pages/connection_page.dart`** — Full implementation. Responsive column strategy from §6.
6. **`pages/configurations_page.dart`** — Full implementation using `YLProfileCard`.

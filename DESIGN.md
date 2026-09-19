# Design Decisions

This document records the architectural, visual, and UX decisions made for FrameWidge.

**Visual design standard**: [shrippen/DesignDefault](https://github.com/shrippen/DesignDefault) — Gruvbox-inspired, warm, dark-first palette with Rajdhani headings. All landing pages, badges, and branding assets follow that shared design language. Plasma widget UI defers to `Kirigami.Theme.*` for interactive elements; only brand accent (`#E8DCC4`) and semantic colors are used for non-theme-dependent elements (icon marks, priority bands, badges).

---

## Architecture

### Client-only plasmoid, no backend fork

The plasmoid is a pure QML frontend. It talks to the existing [framework-control](https://github.com/ozturkkl/framework-control) REST API on `http://127.0.0.1:<port>/api/`. The Rust systemd service handles all privileged operations (EC access via `framework_tool`, fan curve enforcement, power management, telemetry collection).

**Rationale**: The backend is MIT-licensed, stable, and already packaged (AUR, nixpkgs, install script). Forking it would duplicate maintenance without adding value. If API changes are needed in the future, a fork can be introduced then.

### No C++ / CMake build step

The plasmoid is a pure QML package installed via `kpackagetool6`. No native compilation needed. This keeps the install trivial and avoids build-time dependencies.

### HTTP via XMLHttpRequest, not DataEngine

Plasma 5's `executable` DataEngine is deprecated in Plasma 6. Since the backend already exposes a REST API on loopback, `XMLHttpRequest` in QML is the natural choice. CORS is not a blocker because QML is not a browser origin.

---

## Port Discovery

| Priority | Port | Source |
|----------|-------|--------|
| 1 | User-configured (`plasmoid.configuration.servicePort`) | Widget settings dialog |
| 2 | `30912` | AUR/release build default (baked at compile time) |
| 3 | `8090` | Dev default from `.env` |

The health poll tries the configured port. The default is `30912` to match the AUR package.

Polling only runs while the popup is open; the service logs every request to the journal, so background polling (live tray overlay with the popup closed) is opt-in via the `debugBackgroundPolling` setting on the System Info KCM page.

---

## Service States

The widget handles three states:

| State | Condition | UI |
|-------|-----------|-----|
| **offline** | Health poll fails | OfflineHint with install command and systemctl hint |
| **cli_missing** | Health returns `cli_present: false` | Warning about missing `framework_tool` |
| **ok** | Health returns successfully with CLI present | Full tabbed interface |

---

## UI Layout

### Compact representation (tray)

- Custom monochrome chip glyph (`icons/framewidge.svg`), rendered via `Kirigami.Icon { isMask: true }` so it recolors to match the panel like Breeze's own symbolic icons; opacity 0.4 when offline
- Tooltip with CPU temp, fan RPM, battery SoC, and fan mode
- Configurable via `compactDisplay` (temp/RPM/SoC/icon-only), `compactShowIcon` (bool): the latter, when true and a data mode is selected, stacks the icon above the number instead of one replacing the other — and `compactOverlayScale` (int, 50–200 %): scales the data overlay's size
- The overlay text is plain background-free text, colored by the displayed value through user-configurable bands (`compactOverlayBands`, JSON: per mode an ordered list of `{upTo, color}` thresholds, last band open-ended). Band colors are theme tokens (`positive`/`neutral`/`negative`/…, resolved against the active Breeze scheme at render time) or custom `#rrggbb` values picked in the KCM color dialog; any number of bands ≥ 1 works, editable per mode in the KCM with reset-to-defaults. Only the status dot in icon-only mode keeps its own hardcoded temperature grading

### Full representation (popup)

Tabs instead of the web UI's side-by-side panels — a popup can't render four columns.

| Tab | API endpoints | Notes |
|-----|--------------|-------|
| Sensors | `/thermal/history` | Canvas-based line chart, sensor checkboxes, time window slider |
| Fan | `/config` (GET/POST), `/thermal` | Mode selector, manual duty slider, CurveEditor, curve presets (client-side, optionally auto-applied by Plasma Activity), calibration dialog, per-fan override tabs |
| Power | `/power`, `/config` | AC/Battery radio, capability-driven controls (EPP, governor, freq, TDP, thermal) |
| Battery | `/power`, `/config` | Info bar + charge limit slider + rate limit with SoC threshold |

There is no in-popup "Settings" tab: system info, telemetry poll config, the log viewer, and the web UI link all live in the right-click **Configure...** dialog's "System Info" page instead (`ConfigSystemInfo.qml`), alongside the existing "General" page (`ConfigGeneral.qml`) — see "Settings live in one place" below for why.

### Settings live in one place

Configuration used to be split across two places: the widget's own KConfig settings (service port, poll interval, tray display) lived in the right-click "Configure..." dialog, while server-side settings and read-only info (system/version info, telemetry poll rate, logs, web UI link) lived in a "Settings" tab inside the popup. This was confusing — two different places both called "settings" for the same widget. Everything now lives in the Configure dialog, as two KCM pages: **General** (the widget's own KConfig entries) and **System Info** (everything that used to be the popup tab).

The System Info KCM page is fully self-contained: it fetches its own data directly from the backend via `Api.js` using `plasmoid.configuration.servicePort`, rather than reading `root.configData`/`root.thermalData` the way popup tabs do. This is a hard architectural constraint, not a style choice — a KCM page (`ConfigCategory.source`) is loaded into the System Settings/"Configure..." dialog's own QML context, which is a separate object tree from `main.qml`'s `PlasmoidItem` (`root`); it has no access to `root`'s custom properties or functions, only to `plasmoid.configuration` (the KConfigXT-backed settings) which both contexts share.

### Fan curve presets and Activity auto-activation

Saved fan curve presets (name, curve points, hysteresis, rate limit, sensor selection) are stored in the widget's own KConfig (`fanCurvePresetsJson`, a JSON-encoded string — kcfg has no native list-of-objects type) rather than sent to the backend's `/api/config`. That schema belongs to `framework-control`, a project we don't fork or extend (see "Client-only plasmoid" above); an unrecognized `presets` field added to its `fan.curve` object would likely be silently dropped or rejected on the next read.

A preset can optionally be tagged with a Plasma Activity id, in which case `FanPage` switches to it automatically when that Activity becomes current. This uses `org.kde.activities`' `ActivityModel`, tracked via an `Instantiator` (`id`/`name`/`current` roles) rather than any polling — verified empirically against `org.kde.ActivityManager`'s D-Bus API (`busctl --user call org.kde.ActivityManager /ActivityManager/Activities org.kde.ActivityManager.Activities CurrentActivity`) before shipping, since no documentation for this specific QML API surface was found. Auto-activation by *running program* was considered and explicitly rejected: a pure-QML plasmoid has no sanctioned way to enumerate processes without either a native helper (which "No C++ / CMake build step" above rules out) or a new backend endpoint (which the upstream project doesn't accept PRs for).

### Offline hint

When the service is unreachable, the full representation shows:

- Disconnect icon + heading
- Copyable install command (`curl ... | sudo bash`)
- Copyable systemctl start command
- Port info with link to widget settings

---

## Fan Curve Editor

Interactive Canvas element with:

- Grid: 0–100 °C x-axis, 0–100% duty y-axis, 20-unit gridlines
- Click to add point, drag to move, double-click to remove (minimum 2 points)
- Points sorted by temperature after every interaction
- Line segments between points (no spline interpolation in the editor — the backend handles interpolation)

### Calibration

Mirrors the web UI's `CalibrationModal.svelte` logic:

1. Save current fan mode
2. Step through duties [100, 80, 60, 40, 20]
3. At each duty, set manual mode, wait for RPM stability (5-reading window, stdev ≤ 30, timeout 10 s)
4. Record median RPM
5. Append [0, 0], sort, save to `fan.calibration`
6. Restore previous fan mode

---

## Visual Design (Landing Page & Branding)

All web-facing assets follow [shrippen/DesignDefault](https://github.com/shrippen/DesignDefault):

- **Palette**: Gruvbox warm-dark (`--bg0: #282828`, `--fg1: #ebdbb2`, `--accent: #e8dcc4`, `--blue: #83a598`)
- **Typography**: Rajdhani 600/700 for headings, system sans for body, JetBrains Mono for code
- **Layout**: Landing page template (hero → install card → screenshot → features → prerequisites → footer)
- **Badges**: shields.io with `labelColor=1c1c20`, version in `e8dcc4`, tech in `83a598`, license in `a89984`
- **No light mode** for landing pages

### Plasma widget visual rules

- All interactive UI colors from `Kirigami.Theme.*` — never hardcode palette hex for buttons, text, selection
- Brand accent `#E8DCC4` only for: icon mark fill in About/header, version badges
- Canvas charts use `Kirigami.Theme.highlightColor` for the curve line, `Kirigami.Theme.disabledTextColor` for grid, `Kirigami.Theme.textColor` for labels and points
- Sensor line colors: deterministic hash-based from sensor name, HSL lightness tuned per light/dark color scheme (see `ColorGrading.sensorColor`)
- Tab bar icons must be monochrome: use a real Breeze `*-symbolic` icon name via `icon.name` (auto-tints to match theme text color). Always use a real theme icon here, never a custom `icon.source` + custom `contentItem` — `icon.color` does **not** recolor an arbitrary `icon.source` on `QQC2.TabButton` (only named theme icons auto-tint), and a hand-built `contentItem` isn't measured by `QQC2.TabBar`'s width allocation the same way `icon`+`text` is, which visibly overflowed into the next tab when tried for Power. Search the installed Breeze theme (`find /usr/share/icons/breeze -iname '*<concept>*symbolic*'`) for a reasonable semantic fit before picking one; the tray icon (`icons/framewidge.svg`, `Kirigami.Icon { isMask: true }`) is a different, unrelated case — `Kirigami.Icon`'s masking is proven reliable, it's specifically `QQC2.TabButton`'s icon pipeline that doesn't support it
- The popup's width is fixed (`Layout.minimumWidth == maximumWidth == preferredWidth` in `FullRepresentation.qml`); only height is resizable, since the tab content (sliders, combo boxes, the curve graph) doesn't reflow sensibly when squeezed or stretched horizontally

---

## Install Strategy

### install.sh

Wrapper script that installs both backend and plasmoid:

1. Check prerequisites (`kpackagetool6`, `curl`)
2. If `framework-control.service` is not running, offer to install via the official upstream script
3. Clone/download this repo, install plasmoid via `kpackagetool6 -t Plasma/Applet -i package/`

Backend install requires `sudo`; plasmoid install does not.

### Uninstall

`uninstall.sh` removes only the plasmoid. Backend removal is documented separately (upstream's `uninstall-linux.sh`).

### Release channels

The install script offers three channels:

| Channel | Source | Use case |
|---------|--------|----------|
| **Stable** (default) | Latest GitHub release **not** marked pre-release | Recommended for daily use |
| **Beta** | Latest GitHub release tagged as pre-release (`beta`, `alpha`, `rc`) | Early access to new features, may have bugs |
| **Main** | `main` branch HEAD | Bleeding edge, no stability guarantees |

The channel selection is interactive — the user picks `1/2/3` at install time. The script resolves the correct tag or branch via the GitHub API and downloads the matching tarball.

**Current state**: Only a beta release (`v0.1.0-beta`) exists. Once the first stable release is published, the default channel (1) will resolve to it. Until then, users should choose Beta (2) or Main (3).

### AUR / copr

Planned for after MVP. Not yet implemented.

---

## What is NOT ported

These features from the web UI are intentionally excluded:

| Feature | Reason |
|---------|--------|
| RyzenAdj install/uninstall | Windows-only |
| Version mismatch gate | Only relevant for hosted web UI vs embedded |
| DaisyUI themes | Plasma has its own theming |
| Browser shortcuts | Not applicable |
| Update apply (`POST /update/apply`) | Service self-update is better handled by the package manager |

---

## Licensing

- **This project**: MIT
- **Backend**: MIT ([ozturkkl/framework-control](https://github.com/ozturkkl/framework-control) by Kemal Ozturk)
- **No code copied** from the Svelte frontend — the QML is written from scratch against the public API
- **Credit** to the original author in LICENSE and README
- Upstream does not accept PRs — this is an independent project

---

## API Reference (consumed endpoints)

| Method | Path | Used by |
|--------|------|---------|
| GET | `/api/health` | Health polling (all states) |
| GET | `/api/thermal` | Live temps/RPMs, sensor discovery |
| GET | `/api/thermal/history` | SensorsPage graph |
| GET | `/api/power` | PowerPage + BatteryPage (capabilities, state, battery info) |
| GET | `/api/config` | All pages (seed UI from persisted config) |
| POST | `/api/config` | All pages (partial merge to update settings) |
| GET | `/api/system` | ConfigSystemInfo KCM page (CPU, memory, OS) |
| GET | `/api/versions` | ConfigSystemInfo KCM page (BIOS, mainboard, tool version) |
| GET | `/api/logs` | ConfigSystemInfo KCM page (plain text, last 500 lines) |
| GET | `/api/update/check` | ConfigSystemInfo KCM page (optional) |
| GET | `/api/framework_tool/versions` | ConfigSystemInfo KCM page (optional) |

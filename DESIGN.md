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

- Kirigami icon (`cpu`), opacity 0.4 when offline
- Tooltip with CPU temp, fan RPM, battery SoC, and fan mode
- Configurable overlay: temp, RPM, SoC, or icon-only

### Full representation (popup)

Tabs instead of the web UI's side-by-side panels — a popup can't render four columns.

| Tab | API endpoints | Notes |
|-----|--------------|-------|
| Sensors | `/thermal/history` | Canvas-based line chart, sensor checkboxes, time window slider |
| Fan | `/config` (GET/POST), `/thermal` | Mode selector, manual duty slider, CurveEditor, calibration dialog, per-fan override tabs |
| Power | `/power`, `/config` | AC/Battery radio, capability-driven controls (EPP, governor, freq, TDP, thermal) |
| Battery | `/power`, `/config` | Info bar + charge limit slider + rate limit with SoC threshold |
| Settings | `/system`, `/versions`, `/logs`, `/config` | System info, telemetry poll config, log viewer, web UI link |

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
- Sensor line colors: deterministic hash-based from sensor name

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
| GET | `/api/system` | SettingsPage (CPU, memory, OS) |
| GET | `/api/versions` | SettingsPage (BIOS, mainboard, tool version) |
| GET | `/api/logs` | SettingsPage (plain text, last 500 lines) |
| GET | `/api/update/check` | SettingsPage (optional) |
| GET | `/api/framework_tool/versions` | SettingsPage (optional) |

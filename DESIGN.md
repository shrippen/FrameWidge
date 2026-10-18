# Design Decisions

This document records the architectural, visual, and UX decisions made for FrameWidge.

**Visual design standard**: [shrippen/shrippen.github.io](https://github.com/shrippen/shrippen.github.io) — Gruvbox-inspired, warm, dark-first palette with Rajdhani headings. All landing pages, badges, and branding assets follow that shared design language. Plasma widget UI defers to `Kirigami.Theme.*` for interactive elements; only brand accent (`#E8DCC4`) and semantic colors are used for non-theme-dependent elements (icon marks, priority bands, badges).

---

## Architecture

### QML widget plus own service (framewidged)

```
┌──────────────┐  system D-Bus          ┌───────────────────────────────────┐
│ Plasma widget│ ─────────────────────▶ │ framewidged (Rust, root)          │
│ (pure QML)   │  io.github.shrippen.   │  one control loop: fans, charge,  │
└──────────────┘    FrameWidge1         │    history, preset switch         │
                                        │  reads:  sysfs (hwmon cros_ec,    │
                                        │          power_supply)            │
                                        │  writes: framework_tool → EC      │
                                        │  profile: power-profiles-daemon   │
                                        └───────────────────────────────────┘
```

The plasmoid is a pure QML frontend. Everything privileged runs in `framewidged` (`service/`), a small Rust systemd service. It does only what nothing else on the system does: fan curve enforcement, charge limit and rate, and the history for the sensor graph.

- **Reads come from sysfs**, not from `framework_tool`: temperatures and fan speeds from the EC hwmon driver (`cros_ec`, Linux 6.11+), battery and charger from `power_supply`. No process per poll, no EC traffic, no root needed for reading. The sensors carry the names of the current `framework_tool` (0.6.6): temperatures as the EC names them (`cpu@4c`; `framework_tool` 0.6.6 and the kernel's hwmon labels ask the EC with the same command, verified on a Framework 13 AMD), fans by model from the SMBIOS product name (`APU Fan`; `Left Fan`/`Right Fan` on a 16). `sensors::canonical` maps the names `framework_tool` 0.6.5 and older printed (`APU`, `F75303_CPU`, ...), so saved curves keep working. Without the hwmon driver (older kernels) `framework_tool --thermal` reads, under the same names.
- **Writes go through `framework_tool`**: fan duty, auto fan, charge limit and rate. It also reads the charge limit and the firmware versions, which sysfs lacks.
- **Power profiles belong to power-profiles-daemon** (or tuned-ppd): it owns governor, EPP and platform profile, and Plasma's battery applet switches it. The service only reads and sets the profile, so two programs never fight over cpufreq. Until this change the service wrote cpufreq itself and needed a reconciler that waited a minute before overwriting a foreign value.
- **One control loop** instead of a thread per task: each tick reads once, then steps the fans (at the curve's poll interval), the charge settings (every second, written only on change or every ten minutes) and the history (telemetry poll interval).

**Until 1.2** the widget used the REST API of [framework-control](https://github.com/ozturkkl/framework-control) by Kemal Ozturk. framework-control 0.5.5 (October 2026) moved the fan settings into profiles and the widget's fan writes were silently dropped. Upstream takes no PRs, its API changes with its web UI, and the part FrameWidge needs is small and stable: the `framework_tool` calls and output parsers, the cpufreq sysfs files and the curve state machine (all untouched upstream since July 2026). So the service carries that part itself, ported from framework-control (MIT, credited in LICENSE and the source files), and keeps the API schema the widget already spoke.

The EC stays behind `framework_tool` (FrameworkComputer/framework-system, BSD-3): Framework's own tool knows the per-model EC commands; talking to `/dev/cros_ec` directly would make this project responsible for that.

What framewidged leaves out compared to framework-control: web UI, self-update, battery history, its own cpufreq control (see above), TDP/thermal limits via ryzenadj (Windows-only upstream).

### No C++ / CMake build step for the widget

The plasmoid is a pure QML package installed via `kpackagetool6`. The service is a separate binary: release builds download it from the GitHub release (static musl build), the `main` channel builds it with cargo.

### D-Bus with polkit, not HTTP

The service owns `io.github.shrippen.FrameWidge` on the system bus; the widget calls it through Plasma's QML D-Bus module (`org.kde.plasma.workspace.dbus`, Plasma 6.1+) in `js/Api.js`. Replies are JSON strings in the schema below: one stable D-Bus signature while the schema grows.

- **Who may change settings:** polkit action `io.github.shrippen.FrameWidge.configure`, allowed for the active local session without a password, otherwise an admin password. Reading is open to every local user (`service/data/io.github.shrippen.FrameWidge.conf`). With the earlier loopback HTTP API every local process and every web page in a browser could reach the port; the API needed Content-Type and Host checks against pages.
- **No port:** nothing to configure, no clash with framework-control's port.
- **Tests and demo:** the widget only uses the system bus. Tests and the demo start a private `dbus-daemon` and set `DBUS_SYSTEM_BUS_ADDRESS` to it, for the widget and for the stand-in (`tests/fixtures/mock_backend.py`); the service tests run the real binary with `--session` on a private bus. No test or demo switch in the shipped widget.

### Fan safety

`ExecStopPost=framewidged --restore-fan` hands the fans back to the EC's own curve whenever the service stops or crashes, so a fan never stays at a fixed duty without its control loop.

---

## Polling

Polling only runs while the popup is open; background polling (live tray overlay with the popup closed) is opt-in via the `debugBackgroundPolling` setting on the System Info KCM page. framework-control logged every HTTP request to the journal, which was the reason for the opt-in; framewidged logs no calls, so this default can be revisited.

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

| Tab | D-Bus methods | Notes |
|-----|--------------|-------|
| Sensors | `ThermalHistory` | Canvas-based line chart, sensor checkboxes, time window slider |
| Fan | `Config`, `SetConfig`, `Thermal` | Mode selector, manual duty slider, CurveEditor, curve presets (stored by the service, optionally applied by Plasma Activity or by the service on plug/unplug), calibration dialog, per-fan override tabs |
| Power | `Power`, `SetPowerProfile` | AC state and the system power profile (power-profiles-daemon) |
| Battery | `Power`, `Config`, `SetConfig` | Info bar + charge limit slider + rate limit with SoC threshold |

There is no in-popup "Settings" tab: system info, telemetry poll config, and the log viewer all live in the right-click **Configure...** dialog's "System Info" page instead (`ConfigSystemInfo.qml`), alongside the existing "General" page (`ConfigGeneral.qml`) — see "Settings live in one place" below for why.

### Settings live in one place

Configuration used to be split across two places: the widget's own KConfig settings (service port, poll interval, tray display) lived in the right-click "Configure..." dialog, while server-side settings and read-only info (system/version info, telemetry poll rate, logs, web UI link) lived in a "Settings" tab inside the popup. This was confusing — two different places both called "settings" for the same widget. Everything now lives in the Configure dialog, as two KCM pages: **General** (the widget's own KConfig entries) and **System Info** (everything that used to be the popup tab).

The System Info KCM page is fully self-contained: it fetches its own data directly from the service via `Api.js`, rather than reading `root.configData`/`root.thermalData` the way popup tabs do. This is a hard architectural constraint, not a style choice — a KCM page (`ConfigCategory.source`) is loaded into the System Settings/"Configure..." dialog's own QML context, which is a separate object tree from `main.qml`'s `PlasmoidItem` (`root`); it has no access to `root`'s custom properties or functions, only to `plasmoid.configuration` (the KConfigXT-backed settings) which both contexts share.

### Fan curve presets and Activity auto-activation

Saved fan curve presets (`fan.presets`: name, curve, Activity id, power source) are stored by the service. A preset tagged with a power source (`ac` or `battery`) is applied by the service itself when the laptop is plugged in or unplugged, also with the widget closed; it reacts to the change only, so a curve chosen by hand stays until the next plug event. One preset per power source. Up to 1.2 the presets lived in the widget's KConfig (`fanCurvePresetsJson`); `FanPage` moves them into the service once.

A preset can optionally be tagged with a Plasma Activity id, in which case `FanPage` switches to it automatically when that Activity becomes current. This uses `org.kde.activities`' `ActivityModel`, tracked via an `Instantiator` (`id`/`name`/`current` roles) rather than any polling — verified empirically against `org.kde.ActivityManager`'s D-Bus API (`busctl --user call org.kde.ActivityManager /ActivityManager/Activities org.kde.ActivityManager.Activities CurrentActivity`) before shipping, since no documentation for this specific QML API surface was found. Auto-activation by *running program* was considered and explicitly rejected: a pure-QML plasmoid has no sanctioned way to enumerate processes without a native helper (which "No C++ / CMake build step" above rules out); the service could do it, but this was not requested.

### Offline hint

When the service is unreachable, the full representation shows:

- Disconnect icon + heading
- Copyable install command (`curl ... | bash`)
- Copyable systemctl start command

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

All web-facing assets follow [shrippen/shrippen.github.io](https://github.com/shrippen/shrippen.github.io):

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
- **Style setting (System / Kante / Kante Light)**: `visualStyle` in `main.xml`, bound to `KanteStyle.kind` in `main.qml`. System is the default and renders the plain Plasma popup; Kante draws over it (skins, `KanteTabBar`, `KanteEmptyState`, `KantePlasma*` wrappers), never changes the platform controls. The Kante modules in `package/contents/ui` are vendored unchanged (a Plasma Store package cannot use import paths); elements Kante lacks are added to Kante, not built here. Kante 1.9 is vendored. In the Kante styles the fan curve is `KanteCurveEditor` (live sensor readings as `markers`, handles in text colors), the Sensors chart `KanteLineChart` (`axis`, hover read-out, legend as `KanteChip`, lines colored by `KanteStyle.dataColor` in sensor-list order) and the tray color bands `KanteBandSection` (`KanteBandEditor` with `pick`, converted from and to the stored thresholds by `ColorGrading.toKanteBands`/`fromKanteBands`); the offline commands are `KanteCommandBox`. System keeps the Canvas editor and chart and `BandEditor`, which also holds the band state for the settings page.
- The popup's width is fixed (`Layout.minimumWidth == maximumWidth == preferredWidth` in `FullRepresentation.qml`); only height is resizable, since the tab content (sliders, combo boxes, the curve graph) doesn't reflow sensibly when squeezed or stretched horizontally

---

## Install Strategy

### install.sh

Wrapper script that installs both service and plasmoid:

1. Check prerequisites (`kpackagetool6`, `curl`)
2. Download this repo at the chosen channel's tag or `main`
3. Service: the release asset `framewidged-x86_64-linux` (or a cargo build on `main`) to `/usr/local/bin`, `service/data/framewidged.service` to `/etc/systemd/system`, the D-Bus policy to `/etc/dbus-1/system.d`, the polkit action to `/usr/share/polkit-1/actions`, `framework_tool` from FrameworkComputer/framework-system to `/usr/local/lib/framewidge` unless one is on PATH. A framework-control unit is disabled; `Conflicts=` stops it. framewidged imports `/etc/framework-control/config.json` on its first start (fan settings of the active profile, battery, telemetry; its cpufreq settings are left to power-profiles-daemon).
4. Install plasmoid via `kpackagetool6 -t Plasma/Applet -i package/`

Service install requires `sudo`; plasmoid install does not.

### Uninstall

`uninstall.sh` removes the plasmoid and, if confirmed, the service with its settings (`/var/lib/framewidged`).

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
- **Service** (`service/`): MIT. The `framework_tool` parsers and the fan curve state machine are ported from [ozturkkl/framework-control](https://github.com/ozturkkl/framework-control) by Kemal Ozturk (MIT); each such file names its source.
- **framework_tool**: BSD-3-Clause ([FrameworkComputer/framework-system](https://github.com/FrameworkComputer/framework-system)), downloaded by install.sh, not bundled
- **No code copied** from the Svelte frontend — the QML is written from scratch
- **Credit** to the original author in LICENSE and README
- Upstream does not accept PRs — this is an independent project

---

## API Reference (D-Bus)

Bus name `io.github.shrippen.FrameWidge`, object `/io/github/shrippen/FrameWidge`, interface `io.github.shrippen.FrameWidge1`. Every method returns a JSON string unless noted.

| Method | Returns | Used by |
|--------|---------|---------|
| `Health()` | `cli_present`, `service_version` | Health polling (all states) |
| `Thermal()` | `temps` (name → °C), `fans` (name, rpm) | Live temps/RPMs, sensor discovery |
| `ThermalHistory()` | samples `ts_ms`, `temps`, `rpms` | SensorsPage graph |
| `Power()` | `battery` (sysfs plus EC charge limit), `profile` (`active`, `available`) or null | PowerPage, BatteryPage, tray |
| `SetPowerProfile(s)` | nothing; polkit | PowerPage |
| `Config()` | the settings | All pages (seed UI) |
| `SetConfig(s patch)` | the new settings; polkit | All pages |
| `System()` | `cpu`, `memory_total_mb`, `os` | System Info page |
| `Versions()` | BIOS, mainboard, EC and tool versions | System Info page |
| `Logs()` | plain text, last 500 journal lines | System Info page |

The schema of `Config` is in `service/src/config.rs`; `SetConfig` takes a partial patch (objects merge, everything else replaces), validated before it is saved. Settings live in `/var/lib/framewidged/config.json`.

# FrameWidge Roadmap

This document is a code + design review of the current state (as of the `f415f09` commit) and the plan to get FrameWidge from "working prototype" to a sleek, reliable Plasma widget for Framework laptop control.

---

## 1. Review Summary

The project is a clean, single-purpose QML plasmoid with a sensible architecture (thin client over the `framework-control` REST API, no backend fork, no C++ build step). The tab structure, offline handling, and API surface are all reasonable. However, it's an early "vibe coded" prototype: there are real bugs, no tests, inconsistent state management between tabs, and the visual design is functional but not yet "sleek."

### 1.1 Bugs (should fix first)

| # | File | Issue | Impact |
|---|------|-------|--------|
| B1 | `ui/main.qml:59-60` | `switchWidth`/`switchHeight` reference `Kirigami.Units.gridUnit`, but `main.qml` never imports `org.kde.kirigami as Kirigami`. Only `PlasmaCore` is imported. | Likely a `ReferenceError: Kirigami is not defined` at load, or silently falls back to invalid size depending on QML engine leniency. This is exactly the class of bug already fixed twice in recent commits (`StackLayout`, terminal fd3) — the codebase has a pattern of unverified imports. |
| B2 | `ui/js/Api.js:46-60` | `debounce()`/`debouncedPost()` are stubs: `debounce` just calls `fn()` immediately (no real timer, first call establishes a permanent lock in `_debounceTimers` that is *never cleared*, so a second call with the same key becomes a silent no-op forever). Neither function is called anywhere in the codebase. | Dead, misleading code. If someone wires it in later expecting real debouncing, it will silently break input after the first use. |
| B3 | `CompactRepresentation.qml:28-37` | `indicatorColor` is computed (temp-based color grading: green/amber/red) but never bound to anything — the tray icon is always drawn with default icon coloring. | The temperature-based visual warning (the most "at a glance" feature of a tray icon) doesn't actually work. |
| B4 | `QQC2.Slider` usage (Fan/Power/Battery/Sensors pages) | Every `onMoved` handler calls `applyMode()`/`applyField()`/`applyRateLimit()` etc. directly, with **no debouncing**. `onMoved` fires on every pixel of drag, not just on release. | Dragging the TDP or charge-rate slider fires a POST to the backend per pixel — that's tens of HTTP requests per second hitting a service that has to write config and potentially call `framework_tool`. Sluggish UI, wasted backend load, possible EC command spam. |
| B5 | `SettingsPage.qml:105-120` | "Show Logs" button issues **two** requests to `/api/logs`: one via `Api.get` (whose JSON.parse will always fail on plain text, so the callback branch is dead) and a second raw `XMLHttpRequest` for the real text. The dead call is left in with a comment acknowledging it doesn't work. | Wasted request, confusing code, no error surfaced to the user if the raw fetch fails other than a static string. |
| B6 | Cross-tab state | Each page (`FanPage`, `PowerPage`, `BatteryPage`, `SensorsPage`) fetches `/api/config` once in `Component.onCompleted` and keeps its own local mirror of settings. `root.configData` is refreshed centrally after every `saveConfig()`, but the pages never re-read from it — they only ever push their local state outward. | If you change fan mode in the Fan tab, then reopen the popup, or if the config changes externally (web UI, another instance), the tab's sliders/values can silently drift from the backend's actual state until the widget is fully recreated. |
| B7 | `FanPage.qml`, `PowerPage.qml` | Values are bound to defaults (`fanMode: "disabled"`, `manualDutyPct: 50`, capability-driven sliders defaulting to made-up ranges) before the async config/thermal fetch resolves. There's a `configLoaded` flag in `FanPage`/`BatteryPage` but it's **never used** to gate the UI. | Visible flash of wrong/default values on every popup open before the real config loads (typically <200ms, but on a slow poll cycle it's noticeable). |

### 1.2 Design / architecture concerns

- **No request-failure feedback anywhere.** `saveConfig()` swallows failures (`if (ok) loadConfig()`, else nothing) — if a POST to `/api/config` fails (backend restart mid-drag, permission error, malformed capability), the UI shows a slider at a value that was never actually applied, with no error state, toast, or retry.
- **No optimistic-UI / in-flight guard.** Rapid interactions (e.g., toggling fan mode 3x quickly) can result in out-of-order POST responses since there's no request sequencing — a slow first request could overwrite a faster second one when it finally resolves and triggers `loadConfig()`.
- **CurveEditor is mouse-only.** No keyboard alternative to add/move/remove points; not accessible via keyboard/screen reader. Given fan curve is a headline feature, this is worth fixing before calling the widget "polished."
- **Hardcoded sensor chart palette** (`SensorsPage.qml:143,165`) uses 7-9 fixed hex colors rather than theme-derived colors. This is called out as intentional in `DESIGN.md`, but the palette isn't tuned for light mode contrast, and one array (`colors` at line 143) is defined but never used — dead code, the real one is `sensorColor()`.
- **No loading/skeleton states.** Every page just shows stale/default widgets until data arrives; a first-open feels like nothing is happening if the backend is momentarily slow.
- **Fixed popup size** (`Layout.preferredWidth/Height` in `FullRepresentation.qml`) doesn't adapt to font scaling / different panel heights particularly well — no `Layout.maximumHeight` bound to screen constraints, could clip on small displays.
- **No test coverage at all.** No unit tests for the curve editor math (`tempToX`/`xToTemp` round-tripping), no test harness for the Api.js layer, nothing verifying config-merge logic. Given this is "100% vibe coded," regressions in exactly this kind of math are the likeliest failure mode going forward (confirmed by the two recent hotfix commits).
- **No CI.** No `.github/workflows` — nothing lints or type-checks QML/JS before merge, no automated smoke test of `kpackagetool6` install.

### 1.3 Visual design (toward "sleek")

The current UI is functionally organized (tabs mirroring the web UI's panels) but visually plain default-Kirigami:
- Tab bar uses default icons/labels with no visual hierarchy beyond text — a sleek widget benefits from more deliberate iconography and spacing rhythm (the `DESIGN.md` brand accent `#E8DCC4` is currently used nowhere in the actual widget, only reserved for "icon marks" that don't exist yet).
- No app icon / header branding beyond a plain "FrameWidge" `PlasmaExtras.Heading` at 0.8 opacity — feels like a placeholder, not a finished header.
- Charts (`SensorsPage`, `CurveEditor`) are correctly theme-aware for grid/axis but have no hover tooltips, no current-value readout, no animation on data updates — reads as "functional graph" rather than "polished dashboard."
- Compact tray representation is icon+opacity only; the graded color-by-temperature logic exists (`indicatorColor`) but isn't wired in (see B3) — this is the single highest-leverage visual fix, since it's the part of the widget users see 100% of the time.
- No empty/zero states beyond text labels ("—"), no micro-animations for state transitions (offline → online, mode switches).

---

## 2. Roadmap

### Phase 0 — Correctness pass (bug fixes, no new features)
Goal: the widget behaves correctly under normal and adverse conditions before any polish work.

- [ ] Fix B1: add missing `Kirigami` import to `main.qml`, verify popup opens without console errors on real Plasma 6 session.
- [ ] Fix B3: wire `indicatorColor` into the tray icon (recolor `Kirigami.Icon` or add a colored dot/ring overlay driven by temperature state).
- [ ] Fix B4: debounce all slider/spinbox `onMoved`/`onValueModified` → `saveConfig()` calls (e.g. real `Timer`-based debounce per control, ~300–500ms after last change; apply immediately only on release via `onReleased` if `QQC2.Slider` exposes it, otherwise debounce `onMoved`).
- [ ] Fix B5: remove the dead `Api.get` call in `SettingsPage`'s log fetch; keep only the raw XHR, add an error label.
- [ ] Fix B6/B7: introduce a single source of truth — have pages read initial state from `root.configData` (populated once at startup + after every save) instead of each doing its own `/api/config` fetch, and re-sync local mirrors whenever `root.configData` changes elsewhh. Use the existing `configLoaded` flags to gate control visibility/enablement until first load completes.
- [ ] Remove dead code: `debounce`/`debouncedPost` stubs in `Api.js` (replace with a real shared debounce helper used by Phase 0's slider fix, or delete if each page rolls its own `Timer`), the unused `colors` array in `SensorsPage.qml`.
- [ ] Add basic failure feedback: a transient inline banner/toast when `saveConfig` fails, instead of silently reverting.

### Phase 1 — State & reliability hardening
Goal: make multi-tab / multi-instance state consistent and robust to backend hiccups.

- [ ] Centralize config state fully in `main.qml` (`root.configData` as the only fetch point); pages become pure views over `root.configData` + local edit buffers, diffed and pushed via `saveConfig(patch)`.
- [ ] Add request sequencing/guarding (ignore stale POST responses using a monotonically increasing request id) to avoid out-of-order config overwrites.
- [ ] Add a "dirty vs. applied" indicator on controls that have pending unsent changes (relevant once debouncing is in place — user should see it's about to apply, not silently guess).
- [ ] Handle backend restart gracefully mid-session: detect health-poll failure while a popup is open and mid-edit, pause background polling, and show the existing `OfflineHint` without discarding in-progress edits abruptly.
- [x] Add automated tests: `tests/qml/tst_*.qml` unit-test `CurveMath.js`/`ColorGrading.js` (extracted from `CurveEditor`/`CompactRepresentation`/`SensorsPage` for testability), `Api.js` against a mock backend, and the Fan/Power/Battery/Sensors pages' config-seeding, debounce, and patch-building logic via a minimal fake `root`. `tests/smoke/` adds a static package/qmllint/kpackagetool6 check and a `plasmawindowed`-based real-host load test (the only thing that would have caught the missing-Kirigami-import bug, since it needs an actual render). Run via `tests/run_all.sh`; see `tests/README.md` for the how/why.
- [ ] Add a GitHub Actions workflow wiring `tests/run_all.sh` (or at least `run_unit_tests.sh` + `smoke_package.sh`) into CI on a KDE/Plasma-capable runner image; `smoke_plasmawindowed.sh` needs a real Plasma6 + KWin/offscreen-QPA environment, so it may need a container image rather than GitHub's stock Ubuntu runners.

### Phase 2 — Visual redesign ("sleek" pass)
Goal: apply the `DESIGN.md` brand language deliberately inside the widget, not just on the landing page.

**Chosen direction: "Brand-accented Kirigami."** Four directions were proposed (brand-accented Kirigami, dashboard tiles, icon-only sidebar tabs, ambient tray gauge); this one was picked as it stays closest to native Plasma conventions while giving the widget a distinct identity — a small icon-mark header with live status, the `#E8DCC4` accent used deliberately (status dot, progress/active states) instead of generic `QQC2` defaults, and a tighter, more consistent spacing rhythm. The other three remain documented above as alternatives if this direction doesn't hold up once built.

- [x] Design a proper header: `FullRepresentation.qml` now has a real header row — a brand-accent (`#E8DCC4`) icon-mark chip, the "FrameWidge" title, and a live at-a-glance status (colored dot + CPU temp, reusing `ColorGrading.gradeIndicatorColor` from the tray icon) — replacing the plain opacity-0.8 heading. Verified visually against a real `plasmawindowed` session, both against the live backend and via screenshot.
- [x] Redesign the tab bar: kept top tabs (matches the chosen direction's mockup) but added `Kirigami.Separator`s above/below the tab bar and removed the ad-hoc margins in favor of the header/separator/tabbar/content rhythm.
- [x] Polish the Sensors chart and Curve editor: `SensorsPage` now has a hover crosshair with a floating per-series value readout (nearest-sample lookup) and a proper empty state; `CurveEditor` shows a floating "`X°C → Y%`" readout while dragging or hovering a point, and line joins are rounded for smoother rendering. Sensor colors are now theme-aware too: `ColorGrading.sensorColor(name, isDark)` picks a deterministic hue per sensor and renders it via HSL→hex with a lightness tuned by the page's own background-luminance check (`SensorsPage.darkTheme`), instead of one fixed 9-entry hex palette that only read well in one color scheme. Verified visually in a real `plasmawindowed` session.
- [x] Add empty/loading states: Fan/Power/Battery pages show a `BusyIndicator` + "Loading … configuration" row and fade their controls in (`Behavior on opacity`) once `configLoaded` flips, instead of a hard `enabled` cut with stale defaults; `SensorsPage` shows a "Waiting for sensor data…" empty state before any history exists.
- [x] Micro-interactions: offline/online and loading/loaded transitions now cross-fade (`Behavior on opacity` on the `OfflineHint` loader and the main content column, and on the per-page control blocks) instead of hard-cutting; the header's status dot color transitions smoothly (`Behavior on color`) instead of snapping between thresholds.
- [ ] Revisit compact tray representation options: consider a small ring/arc gauge around the icon (temp or duty %) instead of plain icon+overlay text, for a more "native macOS-menu-bar-widget" feel while staying within Plasma tray size constraints. (Not part of the chosen "brand-accented Kirigami" direction — left for later reconsideration, the tray keeps its Phase-1 status-dot treatment.)
- [x] Accessibility pass: `CurveEditor` now supports keyboard control — Tab/Shift+Tab cycles the selected point, arrow keys nudge it (Shift for a 5-unit step), Delete/Backspace removes it (down to the 2-point minimum), with a visible focus ring and a dynamic `Accessible.name`/`description` reflecting the selected point's values. The tray icon (`CompactRepresentation`, the widget's one genuinely icon-only, no-text control) now exposes `Accessible.role/name/description` mirroring its tooltip. The sensor chart Canvas (purely visual otherwise) gets an `Accessible.name` summarizing the latest reading per sensor as text. Purely decorative color swatches/dots that sit next to a text label (legend dots, header status dot, hover-readout dots, brand mark, curve editor's own canvas) are marked `Accessible.ignored` so a screen reader doesn't announce an unlabeled shape twice. Remaining controls (tab buttons, dialog/settings buttons) already carry visible text, so no further labeling was needed there.

### Phase 2 addendum — user-requested refinements
Real-world usage feedback after installing Phase 2, folded in as the same visual pass rather than a new phase.

- [x] Fixed popup content becoming unreachable when the popup is resized shorter than its contents (was landing under the panel): the tab content area is now wrapped in a `QQC2.ScrollView`, and `Layout.minimumHeight` was relaxed (26→18 grid units) since the scroll view is now the real safety net rather than a hard floor.
- [x] Translucent popup background: `Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.TranslucentBackground` in `main.qml`, using Plasma's native translucent/blur panel styling rather than a custom alpha rectangle.
- [x] Sensor tab's temperature axis now autoscales to the visible data's actual min/max (with headroom, rounded to nice 1/2/5×10ⁿ steps) instead of a fixed 0–100°C range that squashed most sensors into a thin band.
- [x] Fan tab: hysteresis/rate-limit and down-rate/poll now share two rows instead of four, each field no longer forced onto its own line.
- [x] Fan curve presets: save the current curve/hysteresis/rate-limit/sensor-selection as a named preset and reload it later, via a small dialog in the Fan tab's Curve section. **Stored in the widget's own KConfig** (`fanCurvePresetsJson`, JSON-encoded) rather than round-tripped through the backend's `/api/config` — that API belongs to an upstream project we don't control (see "No code copied..." below), so an unrecognized `presets` field added to its `fan.curve` schema would likely be silently dropped or rejected on the next GET. **Automatic preset activation was requested too** (by Plasma Activity, by running program) but only partially scoped: Activity-based switching looks genuinely feasible via the `org.kde.activities` QML module already present on the system, but needs the exact "current activity" API in Plasma 6 confirmed before committing to an implementation, so it's deferred rather than shipped half-verified. Program-based switching is **not feasible within this project's architecture** — a pure-QML plasmoid has no sanctioned way to enumerate running processes without either a native helper process (which the "no C++/no backend fork" decision above rules out) or a new endpoint on the upstream backend (which doesn't accept the kind of extension this would need).
- [x] `CurveEditor` now plots the live sensor reading against the curve: a dashed guide at the current temperature (max of the curve's selected sensors, from `FanPage.curveInputTemp`) plus a marker at the duty this curve would command for it right now (linearly interpolated between the two neighboring points) — not just the static configured points.
- [x] Hover tooltips added for AC, TDP, EPP, Governor (`PowerPage`) and charge-rate "C-rate" (`BatteryPage`) — the jargon terms that had no explanation anywhere in the UI.
- [x] Header's live temperature readout enlarged and bolded (was `smallFont`, now 1.3× default size).
- [x] Tray icon's numeric overlay, previously computed (`displayValue`/`displayUnit`) but never actually rendered (dead code), is now wired up: temp/rpm/soc modes show the live number itself (auto-sized to the tray slot via `fontSizeMode: Text.Fit`) instead of just an icon, while "icon" mode keeps the plain icon + status dot. This is the toggle the existing `compactDisplay` setting already implied but didn't deliver.
- [ ] **Tray icon redesign is proposed, not decided.** Five monochrome/symbolic (Breeze-style, `currentColor`, no gradients) concepts were built off the landing page's CPU-chip mark — outlined chip w/ pins, bold pinless silhouette, chip+fan-blade hybrid, chip+thermometer, and a minimal cross-pin variant — and shown at real tray sizes (16/22px) on light and dark panels in a comparison artifact. Swapping `Plasmoid.icon`/`CompactRepresentation`'s `Kirigami.Icon` source to a real SVG resource is a small follow-up once one is chosen (or a mix is specified).

### Phase 3 — Feature rounding & release readiness
Goal: close remaining gaps vs. the web UI (where valuable) and prepare for a stable release / packaging.

- [ ] Re-evaluate the "What is NOT ported" list in `DESIGN.md` now that the core is stable — confirm no regressions push any of those back into scope accidentally.
- [ ] AUR / COPR packaging (already flagged as "planned for after MVP" in `DESIGN.md`).
- [ ] Promote the first stable GitHub release once Phase 0–1 land, so `install.sh`'s default "Stable" channel resolves to something real (currently only a beta exists).
- [ ] Expand `README.md`/landing page with a short GIF/screenshot of the redesigned UI once Phase 2 lands.

---

## 3. Suggested order of work

1. **Phase 0** end-to-end (all items are small, isolated fixes — can likely be done in one focused session/PR).
2. **Phase 1** items B6/B7 refactor (config centralization) before Phase 2 visual work, since redesigning components that are about to have their state model rewritten would mean redoing layout twice.
3. **Phase 2** visual redesign, ideally validated live against a real Plasma 6 session (per the "test UI changes in-browser/app before reporting done" rule — here that means loading the plasmoid via `kpackagetool6 -i` and visually checking each tab, both themes, both online/offline states).
4. **Phase 3** once the widget is functionally and visually solid.

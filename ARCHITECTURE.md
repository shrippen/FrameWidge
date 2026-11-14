# Architecture

How this repository is meant to be built. Where the code differs today is listed under
"Known deviations". Change this file in the PR that changes the structure.

## What it does

A Plasma widget for Framework laptops: it shows temperatures, fan speeds, battery and
power profile, and lets the user set a fan curve and a charge limit. A small service
running as root does the work on the hardware; the widget only talks to that service.

## Building blocks

| Path | Its one task |
|---|---|
| `service/src/dbus.rs` | The service's interface for the widget, on the system bus. The schema is described in `DESIGN.md`. |
| `service/src/control.rs` | The one control loop: steps fans, charge settings and history, each at its interval. |
| `service/src/fan.rs`, `battery.rs`, `telemetry.rs` | The rules: fan curve with hysteresis, keeping the charge limit, the recent history for the graph. |
| `service/src/config.rs` | The settings on disk and their defaults, in the schema the widget reads and writes. |
| `service/src/sensors.rs` | One set of sensor names and readings, whichever driver produced them. A shared vocabulary, not a layer. |
| `service/src/tool.rs`, `parse.rs`, `sysfs.rs` | The drivers: `framework_tool` (writes to the embedded controller) with the parsers of its output, and the kernel's view (reads). |
| `service/src/profiles.rs`, `system.rs` | The system's power profile through its own daemon; host facts and the service log. |
| `service/src/main.rs`, `service/data/` | Start and wiring of the service; its systemd unit, D-Bus policy and polkit action. |
| `package/contents/ui/js/Api.js` | The widget's only way to the service. |
| `package/contents/ui/js/` (other files) | Pure logic without QML: colour bands, curve coordinates, shaping the history for the chart. |
| `package/contents/ui/*.qml` | The widget: the panel item, the popup with its pages (fan, sensors, battery, power), the settings pages, the curve editor. |
| `package/contents/ui/Kante/`, `KantePlasma/` | Synced copies of the design system. Never edited here. |
| `package/contents/config/`, `package/metadata.json` | The widget's own settings and its description for Plasma. |
| `tests/`, `service/tests/` | QML unit tests against a stand-in service, smoke tests; tests of the service. |
| `demo/` | A stand-in service with made-up data for screenshots. Not in a release. |
| `install.sh`, `scripts/`, `po/`, `dist/`, `docs/`, `contrib/` | Installing the service, packaging and release notes, translations, released packages, landing page and store text, a patch for Plasma. |
| `tools/` | The structure check (synced copy). |

## Layers

```
 widget (user, Plasma)                    service (root, systemd)

 pages, editors (QML) ─► js/ pure logic
        │
        ▼
   js/Api.js ────── system bus ──────►  dbus.rs: the interface
                                          │ settings, history   │ reads for an answer
                                          ▼                     │ (battery, versions,
                          config ◄── control loop               │  profile, host)
                                          │                     │
                                          ▼                     │
                          fan, battery, telemetry (the rules)   │
                                          │ fan duty, charge    │
                                          ▼                     ▼
                  drivers: tool + parse (framework_tool), sysfs (kernel),
                           profiles (power profile daemon), system (host)

 sensors.rs: the names and readings every block above shares; it uses none of them
```

- The widget never touches hardware, files of the system or programs. Everything goes
  through `Api.js` to the service; no other file talks to D-Bus.
- The service is the one source of what a setting means and of its default. The widget
  shows and edits what the service reports and keeps no copy of defaults.
- What a fan curve means (its end points, hysteresis) is decided in `fan.rs`. Where the
  widget must draw the same curve, it uses one function that a test holds equal to the
  service's numbers.
- In the service only the drivers know `framework_tool`, its output and sysfs paths.
  The rules read the names and readings of `sensors.rs` and write through the functions
  of the `tool` driver.
- `dbus.rs` decides nothing. It changes settings through `config`, and for an answer
  it may read a driver directly. Of the drivers it writes only the power profile; fans
  and charging are written by the rules alone.
- Logic of the widget that needs no QML lives in `js/` and has tests; a page holds
  layout and wiring.
- A thing shown in both styles (system, Kante) has its texts, commands and rules once;
  the two styles differ in looks only.
- A colour for a value or a sensor is chosen in `js/ColorGrading.js`, nowhere else.
- The stand-ins for the service (`tests/fixtures/`, `demo/backend.py`) answer in the
  service's schema and with its defaults.
- The widget offers only what works: no page, dialog or field nothing reaches.

## Where new things go

| Change | Touch |
|---|---|
| A new value from the hardware | A driver (`sysfs.rs` or `tool.rs` with `parse.rs`), `sensors.rs`, `dbus.rs`, `DESIGN.md`, both stand-ins, then `Api.js` and a page |
| A new setting | `config.rs` (name and default), the rule that uses it, `DESIGN.md`, the page that edits it, both stand-ins |
| A new rule for fans or charging | `fan.rs` or `battery.rs`, with a test in the service |
| A new page or control in the popup | A QML file in `package/contents/ui/`; its logic in `js/` with a test in `tests/qml/`; new texts through `po/update.sh` (German included) |
| A new colour rule | `js/ColorGrading.js` |
| A design element that is missing | Kante, then `scripts/sync-kante.sh`; never the copies here |
| Something run as root or installed on the system | `service/data/`, `install.sh`; the owner confirms |
| A release | The steps in `RELEASE.md`: `CHANGELOG.md`, the version in `package/metadata.json` and `service/Cargo.toml`, landing page |

## Known deviations

- The calibration dialog and the per-fan tabs are in the code but reach nothing; the
  service reports a field it never fills (`AUDIT.md`, finding 1).
- The curve editor computes the curve beyond its last point differently from the service
  (`AUDIT.md`, finding 2).
- A sensor's colour is chosen in two pages by different rules (`AUDIT.md`, finding 3).
- The "service unreachable" hint exists once per style with the same texts and commands
  (`AUDIT.md`, finding 4).
- Colour bands and theme colours stand several times; the popup's header uses its own
  limits (`AUDIT.md`, finding 6).
- The fan page has four tasks and holds logic that belongs in `js/`
  (`AUDIT.md`, finding 7).
- Two more pages hold logic without QML: the sensors page shapes the history and picks
  the axis steps, the curve editor places captions and keeps points in order
  (not in `AUDIT.md`).
- The defaults stand in the service, in the widget and in the test stand-in, which
  already differs (`AUDIT.md`, finding 8).

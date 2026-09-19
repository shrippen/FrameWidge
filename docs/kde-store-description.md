# FrameWidge — KDE Store Listing

Text for the store.kde.org submission ("Pling"/GHNS metadata). Not shipped
inside the plasmoid package — kept in `docs/` as the source of truth for
copy-pasting into the store form.

## Short description (tagline, ~1 sentence)

Native KDE Plasma 6 system tray widget for Framework Laptops — fan curves,
power profiles, battery limits, and live sensor telemetry, right from your
panel.

## Full description

**⚠️ 100% vibe coded.** Every QML file and script in this project was
generated through AI-assisted development — no line was written by hand.
Use at your own risk, and please report bugs on
[GitHub](https://github.com/shrippen/FrameWidge/issues)!

**FrameWidge** is a native KDE Plasma 6 widget for Framework Laptops (13 and
16, AMD and Intel). It lives in your system tray and gives you full control
over fans, power profiles, and battery — no terminal required.

This is **not** a fork of anything. FrameWidge is an independent Plasma
frontend that talks to the REST API of
[framework-control](https://github.com/ozturkkl/framework-control) by Kemal
Ozturk, a small systemd service that already does the hard work of talking to
the embedded controller via `framework_tool`. FrameWidge is pure QML — no C++
compilation, no bundled daemon — it just polls and configures that existing
service over `http://127.0.0.1:30912`.

### Features

- **Fan Control** — Auto mode, manual duty slider, and a custom curve editor
  with drag-and-drop points, hysteresis, rate limiting, and per-fan overrides
  on the Framework 16. Includes a calibration wizard for accurate RPM
  readouts.
- **Sensors** — Live temperature graphs with history, per-sensor selection,
  and a configurable time window.
- **Power** — Separate AC/Battery profiles, EPP, CPU governor, frequency
  limits, TDP, and thermal controls — all driven by what your hardware
  actually supports.
- **Battery** — Live charge/discharge wattage, health, cycle count, charge
  limit (25–100%), and rate limiting with an optional state-of-charge
  threshold.
- **System Tray** — Compact icon with a configurable overlay (temperature,
  RPM, or battery %), a rich tooltip with live stats, and a dimmed icon when
  the backend is unreachable.
- **Guided Setup** — If the backend service isn't installed or running yet,
  the widget shows a friendly setup screen with a copyable install command
  instead of failing silently.

### Requirements

- A **Framework Laptop** (13 or 16, AMD or Intel)
- **KDE Plasma 6** (Wayland or X11)
- Linux with systemd (Arch, Fedora, NixOS, etc.)
- The **framework-control** backend service — see below

### Important: install the backend service too

This widget is a *frontend only*. Installing it from the KDE Store gives you
the plasmoid, but the backend service that actually reads sensors and
controls fans (`framework-control`) is a separate systemd service and is
**not** installed automatically through the Store. Without it, the widget
starts up fine and shows a "Service Not Reachable" screen with the install
command ready to copy — it will not do anything useful until that service is
running.

Install the backend with:

```bash
curl -fsSL https://raw.githubusercontent.com/ozturkkl/framework-control/main/install-linux.sh | sudo bash
```

or via the [AUR](https://aur.archlinux.org/packages/framework-control) /
[nixpkgs](https://github.com/NixOS/nixpkgs/tree/master/pkgs/by-name/fr/framework-control)
package for your distribution.

*Optional:* the Store install doesn't copy FrameWidge's app icon into your
icon theme, so the widget picker, the tray's "Customize" menu, and the
Configure dialog's window icon fall back to a generic icon (the tray icon
itself is unaffected). To fix that cosmetic detail, copy
`contents/icons/hicolor/scalable/apps/framewidge.svg` from the installed
package to `~/.local/share/icons/hicolor/scalable/apps/framewidge.svg`.

For the one-command installer that sets up both the backend and the widget
together, see the [GitHub repository](https://github.com/shrippen/FrameWidge)
and [project page](https://shrippen.github.io/FrameWidge/).

### License

MIT. Based on [framework-control](https://github.com/ozturkkl/framework-control)
by Kemal Ozturk (MIT License).

## Tags / categories

`framework`, `laptop`, `fan-control`, `hardware`, `system-tray`, `sensors`,
`battery`, `power-management`, `plasma6`

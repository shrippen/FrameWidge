# FrameWidge — KDE Store Listing

Text for the store.kde.org submission ("Pling"/GHNS metadata). Not shipped inside the plasmoid package — kept in `docs/` as the source of truth for copy-pasting into the store form.

## Short description (tagline, ~1 sentence)

Native KDE Plasma 6 system tray widget for Framework Laptops — fan curves, power profiles, battery limits, and live sensor telemetry, right from your panel.

## Full description

**⚠️ 100% vibe coded.** Every QML file and script in this project was generated through AI-assisted development — no line was written by hand. Use at your own risk, and please report bugs on [GitHub](https://github.com/shrippen/FrameWidge/issues)!

**FrameWidge** is a native KDE Plasma 6 widget for Framework Laptops (13 and 16, AMD and Intel). It lives in your system tray and gives you full control over fans, power profiles, and battery — no terminal required.

FrameWidge is pure QML. The privileged work is done by its own small systemd service, `framewidged`, which talks to the embedded controller through Framework's `framework_tool` and serves the widget over the system D-Bus; polkit lets the person at the laptop change settings without a password. Parts of the service are ported from [framework-control](https://github.com/ozturkkl/framework-control) by Kemal Ozturk, FrameWidge's backend up to 1.2.

### Features

- **Fan Control** — Auto mode, manual duty slider, and a custom curve editor with drag-and-drop points, hysteresis, rate limiting, and per-fan overrides on the Framework 16. Includes a calibration wizard for accurate RPM readouts.
- **Sensors** — Live temperature graphs with history, per-sensor selection, and a configurable time window.
- **Power** — The system power profile (Power Saver, Balanced, Performance) via power-profiles-daemon or tuned-ppd, the same switch as Plasma's battery applet.
- **Battery** — Live charge/discharge wattage, health, cycle count, charge limit (25–100%), and rate limiting with an optional state-of-charge threshold.
- **System Tray** — Compact icon with a configurable overlay (temperature, RPM, or battery %), a rich tooltip with live stats, and a dimmed icon when the backend is unreachable.
- **Guided Setup** — If the backend service isn't installed or running yet, the widget shows a friendly setup screen with a copyable install command instead of failing silently.

### Requirements

- A **Framework Laptop** (13 or 16, AMD or Intel)
- **KDE Plasma 6.1** or newer (Wayland or X11)
- Linux with systemd (Arch, Fedora, NixOS, etc.)
- The **framewidged** service — see below

### Important: install the service too

Installing the widget from the KDE Store gives you the plasmoid only. The service that actually reads sensors and controls fans (`framewidged`) is a systemd service and is **not** installed through the Store. Without it, the widget starts up fine and shows a "Service Not Reachable" screen with the install command ready to copy — it will not do anything useful until that service is running.

Install it (with the widget) with:

```bash
curl -fsSL https://raw.githubusercontent.com/shrippen/FrameWidge/main/install.sh | bash
```

If framework-control is installed, the script stops and disables it and the service takes over its fan and battery settings (its power settings are left to power-profiles-daemon).

*Optional:* the Store install doesn't copy FrameWidge's app icon into your icon theme, so the widget picker, the tray's "Customize" menu, and the Configure dialog's window icon fall back to a generic icon (the tray icon itself is unaffected). To fix that cosmetic detail, copy `contents/icons/hicolor/scalable/apps/framewidge.svg` from the installed package to `~/.local/share/icons/hicolor/scalable/apps/framewidge.svg`.

Or skip the Store and use the one-command installer, which sets up both the backend and the widget:

```bash
curl -fsSL https://raw.githubusercontent.com/shrippen/FrameWidge/main/install.sh | bash
```

More on the [GitHub repository](https://github.com/shrippen/FrameWidge) and the [project page](https://shrippen.github.io/FrameWidge/).

### License

MIT. The service ports parts of [framework-control](https://github.com/ozturkkl/framework-control) by Kemal Ozturk (MIT License).

## Tags / categories

`framework`, `laptop`, `fan-control`, `hardware`, `system-tray`, `sensors`, `battery`, `power-management`, `plasma6`

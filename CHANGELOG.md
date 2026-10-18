# Changelog

## Unreleased

### Changed

- **Own service instead of framework-control.** framework-control 0.5.5 moved the fan settings into profiles; the Fan tab could no longer read or change them. FrameWidge now brings its own backend, `framewidged` (Rust, `service/`): fan curve and manual duty (also per fan), charge limit and charge rate, sensor history. It reads sensors and battery from the kernel (sysfs) and writes to the EC through Framework's `framework_tool`.
- **D-Bus instead of HTTP.** The widget talks to the service over the system bus; changing settings is checked by polkit (free for the person at the laptop, an admin password for anyone else). The service port setting is gone. Needs Plasma 6.1 or newer.
- **Power tab: the system power profile.** It switches power-profiles-daemon or tuned-ppd (Power Saver, Balanced, Performance), the same setting as Plasma's battery applet. The separate AC/battery settings for governor, EPP, frequency limits, TDP and thermal limit are gone: they fought with that daemon over the same files.
- **Fan curve presets live in the service.** A preset can switch on by itself when the laptop is plugged in or unplugged, also with the widget closed. Presets saved with 1.2 are moved over once.
- Sensors carry the names of the current `framework_tool` (0.6.6): temperatures as the EC names them (`cpu@4c` for the APU), fans by model (`APU Fan`). Fan curves with the names of `framework_tool` 0.6.5 and older (`APU`, `F75303_CPU`, ...) are renamed on load.
- `install.sh` installs `framewidged`, its D-Bus policy and polkit action, and `framework_tool` if missing, and stops and disables framework-control. On its first start framewidged takes over `/etc/framework-control/config.json` (fan settings of the active profile, calibration of the first fan, battery, telemetry).
- When the service stops or crashes, the fans go back to the firmware's own curve.
- System Info page: the web UI link is gone (framewidged has none).
- `uninstall.sh` offers to remove the service too.

### Added

- Style setting (System / Kante / Kante Light) for the popup. System is the default and unchanged. Kante 1.9 is vendored in `package/contents/ui/Kante` and `KantePlasma`.
- Kante styles use Kante elements instead of local ones: `KanteCurveEditor` for the fan curve (live readings as its markers), `KanteLineChart` (hover read-out, axis) and `KanteChip` legend for the Sensors tab, `KanteBandEditor` for the tray color bands in the settings, `KanteCommandBox` for the install and start commands. Sensor colors come from `KanteStyle.dataColor`. System keeps the Canvas editor and chart.
- `Copied` and style-setting strings with German translations (`po/update.sh`).

### Changed

- No tab scrolls at the default popup size: the popup is taller (35 grid units, enough for the Fan tab) and each tab scrolls by its own height, not the tallest tab's. The Sensors chart has a fixed height, so the sensor choice and time range show without scrolling.
- Sensor line colors in the System style are spread by the sensor's position (one hue step of 137.5° each); CPU and Battery no longer share one salmon. Kante styles keep `KanteStyle.dataColor`.
- Vendored Kante 1.9.1 (readable accent text on the platform colors, visible empty check boxes, round line chart axis steps).

- Kante 1.4 -> 1.9 (`scripts/sync-kante.sh`). `KanteDialogSkin` is a QtObject now; the dialogs hold it as one. 1.8: `KanteChip` frames colours near the ground (`nearGround`), `KanteSwatch` sizes; no widget code change needed (no swatch or callout used directly). 1.9: `KanteCheckSkin` labels and `KanteFieldSkin` spin box text readable on dark Kante under a light Plasma scheme.

### Fixed

- `CalibrationDialog` and the preset dialog in Kante: the title strip and buttons are Kante's now (`KanteDialogSkin` themes header and footer); before, the platform's light strip stayed on the dark card.
- `PowerPage` visibility bindings are boolean (real Kirigami warned about `undefined`).
- Fan page fits the 432 px popup: hysteresis, rate limits and poll interval stack one per row below 32 grid units (were two per row, clipping the curve editor and spin box arrows).
- System curve editor: marker captions move left of the guide when a point's handle would cover them ("CPU 58°" showed as "U 58°").
- Kante offline state: headings no longer truncate ("INSTA..."), and the state has real side margins (the Loader ignored `Layout.margins`).

### Known gaps

- Kante's line chart has no time axis; the hover read-out shows the time.

## 1.2

### Changed

- New logo: the tray uses the monochrome variant (follows the panel's text color), the app icon uses the variant with the color accent.
- Packaged `dist/framewidge-1.2.plasmoid`.

## 1.1

### Fixed

- The tray overlay (temperature/RPM/SoC) now loads its data at startup instead of staying empty until the popup is opened for the first time.

### Added

- Packaged `dist/framewidge-1.1.plasmoid` for KDE Store upload.
- Install script mentioned in the KDE Store description; new logo (`dist/framewidge-logo.png`).
- Screenshots for the store listing.

## 1.0

- Initial release.

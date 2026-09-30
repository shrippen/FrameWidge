# Changelog

## Unreleased

### Added

- Style setting (System / Kante / Kante Light) for the popup. System is the default and unchanged. Kante 1.9 is vendored in `package/contents/ui/Kante` and `KantePlasma`.
- Kante styles use Kante elements instead of local ones: `KanteCurveEditor` for the fan curve (live readings as its markers), `KanteLineChart` (hover read-out, axis) and `KanteChip` legend for the Sensors tab, `KanteBandEditor` for the tray color bands in the settings, `KanteCommandBox` for the install and start commands. Sensor colors come from `KanteStyle.dataColor`. System keeps the Canvas editor and chart.
- `Copied` and style-setting strings with German translations (`po/update.sh`).

### Changed

- Kante 1.4 -> 1.9 (`scripts/sync-kante.sh`). `KanteDialogSkin` is a QtObject now; the dialogs hold it as one. 1.8: `KanteChip` frames colours near the ground (`nearGround`), `KanteSwatch` sizes; no widget code change needed (no swatch or callout used directly). 1.9: `KanteCheckSkin` labels readable on dark Kante under a light Plasma scheme.

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

# Changelog

## Unreleased

### Added

- Style setting (System / Kante / Kante Light) for the popup. System is the default and unchanged. Kante 1.6 is vendored in `package/contents/ui/Kante` and `KantePlasma`.
- Kante styles use Kante elements instead of local ones: `KanteCurveEditor` for the fan curve, `KanteLineChart` (with hover read-out) and `KanteChip` legend for the Sensors tab, `KanteBandEditor` for the tray color bands in the settings, `KanteCommandBox` for the install and start commands. Sensor colors come from `KanteStyle.dataColor`. System keeps the Canvas editor and chart.
- `Copied` string (translations: run `po/update.sh`).

### Changed

- Kante 1.4 -> 1.6 (`scripts/sync-kante.sh`). `KanteDialogSkin` is a QtObject now; the dialogs hold it as one.

### Known gaps (missing in Kante, to be added there)

- Curve editor: no live markers. The current sensor readings show as chips under it.
- Line chart: no axis labels; the scale is set to whole tens of the data.
- Band editor: no color picker (swatches cycle through the theme colors, custom colors set earlier are kept until changed); the first row's value is fixed at 0.

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

# Changelog

## Unreleased

### Added

- Style setting (System / Kante / Kante Light) for the popup. System is the default and unchanged. Kante 1.7 is vendored in `package/contents/ui/Kante` and `KantePlasma`.
- Kante styles use Kante elements instead of local ones: `KanteCurveEditor` for the fan curve (live readings as its markers), `KanteLineChart` (hover read-out, axis) and `KanteChip` legend for the Sensors tab, `KanteBandEditor` for the tray color bands in the settings, `KanteCommandBox` for the install and start commands. Sensor colors come from `KanteStyle.dataColor`. System keeps the Canvas editor and chart.
- `Copied` string (translations: run `po/update.sh`).

### Changed

- Kante 1.4 -> 1.7 (`scripts/sync-kante.sh`). `KanteDialogSkin` is a QtObject now; the dialogs hold it as one.

### Fixed

- Kante offline state: headings no longer truncate ("INSTA..."), and the state has real side margins (the Loader ignored `Layout.margins`).

### Known gaps

- `CalibrationDialog` in Kante: the dialog's title strip is still the platform's (`KanteDialogSkin` only replaces the background). Not changed without a real Kirigami dialog to check against.
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

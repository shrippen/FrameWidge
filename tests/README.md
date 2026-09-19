# Tests

- **Unit tests** (`tests/qml/`): page logic (config seeding, debouncing, patch building, coordinate math, color grading). Headless via `qmltestrunner`, no Plasma session.
- **Smoke tests** (`tests/smoke/`): broken imports, invalid package, widget failing to load in a real Plasma host.

```sh
tests/run_all.sh                               # everything
tests/run_unit_tests.sh                        # all unit tests
tests/run_unit_tests.sh 'tst_FanPage*.qml'     # one file
tests/smoke/smoke_package.sh                   # lint + package validation
tests/smoke/smoke_plasmawindowed.sh            # real-host load test
```

## Unit tests

The pages (`FanPage`, `PowerPage`, `BatteryPage`, `SensorsPage`) use an unqualified `root`, resolved via id scope. In the widget it is the `PlasmoidItem` in `main.qml`. Each `tst_*PageLogic.qml` recreates it as `Item { id: root }` with only the properties and functions the page touches (`configData`, `thermalData`, `powerData`, `saveConfig()`, ...). No mocking framework, no Plasma host.

`i18n()` is injected by Plasma and undefined in `qmltestrunner`. The resulting `ReferenceError: i18n is not defined` warnings are harmless. A real failure is a `FAIL!` line.

`tst_Api.qml` and `tst_SensorsPageLogic.qml` make real HTTP calls. `run_unit_tests.sh` starts `tests/fixtures/mock_backend.py` (stdlib-only, emulates the used subset of the framework-control API) and writes its port to `tests/.runtime/mock_port.txt` (gitignored). QML has no `Qt.getenv()`, hence the file. Without it, network tests `skip()`.

Test-only routes of the mock:

- `GET /__requests`: log of received requests. Asserts a debounced slider drag sends one call, not one per pixel.
- `POST /__reset`: clears the log, resets `/api/config` to defaults.

`main.qml` is not unit tested. Instantiating a `PlasmoidItem` outside a Plasma containment fails with `Could not create attached properties object 'PlasmaQuick::PlasmoidAttached'`. The smoke test covers it.

## Smoke tests

`smoke_package.sh` runs static checks:

- `qmllint` errors only. Warnings are noise: standalone lint can't resolve `plasmoid`/`i18n`.
- Valid `metadata.json` and `config/main.xml`.
- Every `cfg_*` alias in `ConfigGeneral.qml` has an `<entry>` in `main.xml`.
- `kpackagetool6` accepts the package.

Installs into a scratch `XDG_DATA_HOME`.

`smoke_plasmawindowed.sh` loads the complete widget in a real applet host via `plasmawindowed`, offscreen (`QT_QPA_PLATFORM=offscreen`). It uses scratch `XDG_DATA_HOME`/`XDG_CONFIG_HOME` and never contacts a real backend. Whatever listens on the default port is what gets tested, so the offline path is covered too. It catches errors that only appear on render, such as the earlier missing `Kirigami` import.

Both scripts skip checks whose tool (`qmllint`, `kpackagetool6`, `plasmawindowed`) is missing from `PATH`, and print why. Target: a KDE Plasma 6 dev machine, not generic CI.

# Tests

Two layers, because the plasmoid has two kinds of code that need two kinds
of harness:

- **Unit tests** (`tests/qml/`) for the page components' logic (config
  seeding, debouncing, patch building, coordinate math, color grading).
  These run headless via Qt Quick Test (`qmltestrunner`) and don't need a
  Plasma session.
- **Smoke tests** (`tests/smoke/`) for the things a unit test structurally
  can't catch: a broken import, an invalid package, or the widget failing
  to even load inside a real Plasma host.

Run everything:

```sh
tests/run_all.sh
```

Or just one layer:

```sh
tests/run_unit_tests.sh                        # all unit tests
tests/run_unit_tests.sh 'tst_FanPage*.qml'      # one file
tests/smoke/smoke_package.sh                    # lint + package validation
tests/smoke/smoke_plasmawindowed.sh             # real-host load test
```

## Why the unit tests are structured the way they are

`FanPage.qml`, `PowerPage.qml`, `BatteryPage.qml`, and `SensorsPage.qml`
read/write an unqualified `root` identifier that QML resolves through the
surrounding id scope, not an import — in the real widget `root` is the
`PlasmoidItem` in `main.qml`. Each `tst_*PageLogic.qml` file recreates just
enough of that scope: a plain `Item { id: root }` with the handful of
properties/functions the page under test actually touches
(`configData`, `thermalData`, `powerData`, `saveConfig()`, ...). No mocking
framework, no Plasma host - just the same id-lookup mechanism the app
already relies on.

These pages also call the global `i18n()` function, which is normally
injected by the real Plasma host and is genuinely undefined in a bare
`qmltestrunner` run. QML treats a binding that throws as a per-binding
warning, not a fatal error, so component construction still succeeds and
the page's own functions still work correctly - you'll see a wall of
`ReferenceError: i18n is not defined` warnings in the output. **That's
expected and harmless**; a real failure shows up as a `FAIL!` line, not a
`QWARN`.

Two files (`tst_Api.qml`, `tst_SensorsPageLogic.qml`) also make real HTTP
calls (`Api.js` wraps `XMLHttpRequest`, and `SensorsPage` uses it
directly), so `run_unit_tests.sh` starts `tests/fixtures/mock_backend.py` -
a stdlib-only Python server that emulates the subset of the
`framework-control` REST API the widget consumes - and writes its
ephemeral port to `tests/.runtime/mock_port.txt` (gitignored) for the QML
tests to read (QML has no `Qt.getenv()`, hence the file instead of an env
var). Tests needing the network `skip()` themselves with a clear message
if that file isn't present, so `qmltestrunner -input tests/qml/tst_Api.qml`
still runs standalone - it just skips the network-dependent cases.

The mock backend also exposes two test-only routes: `GET /__requests`
(a log of every request it's received, used to assert that a debounced UI
interaction really produced only one HTTP call instead of one per pixel of
a slider drag) and `POST /__reset` (clears that log and resets `/api/config`
back to defaults between tests).

`main.qml` itself is **not** unit tested: it's a `PlasmoidItem`, and
attempting to instantiate one outside a real Plasma containment fails with
`Could not create attached properties object 'PlasmaQuick::PlasmoidAttached'`
(verified while writing this suite). That's exactly what
`smoke_plasmawindowed.sh` is for instead.

## Why the smoke tests are structured the way they are

`smoke_package.sh` catches static problems: `qmllint` errors (not
warnings - a standalone lint run legitimately can't resolve `plasmoid`/
`i18n` either, so warnings are noise, but a real `Error:` means a syntax
problem), invalid `metadata.json`/`config/main.xml`, `ConfigGeneral.qml`
referencing a `cfg_*` alias with no matching `<entry>` in `main.xml`, and
whether `kpackagetool6` accepts the package at all. It installs into a
scratch `XDG_DATA_HOME`, never your real one.

`smoke_plasmawindowed.sh` is the only check that loads the actual,
complete widget (`main.qml` and everything under it) inside a real Plasma
applet host, via KDE's own `plasmawindowed` tool, offscreen
(`QT_QPA_PLATFORM=offscreen`) so it runs headless. It installs into a
scratch `XDG_DATA_HOME`/`XDG_CONFIG_HOME` too, so it never touches your
real widget list, and it never talks to a real Framework laptop backend -
whatever is (or isn't) listening on the widget's configured default port
is exactly what it exercises, so it validates the offline path just as
legitimately as the online one. This is the test that would have caught
the missing-`Kirigami`-import bug fixed in an earlier pass: that bug only
manifests once something actually tries to *render* the widget, which no
amount of qmllint or unit testing on its own would catch.

Both scripts skip (not fail) individual checks whose tool
(`qmllint`, `kpackagetool6`, `plasmawindowed`) isn't on `PATH`, printing
why - this suite targets a KDE Plasma 6 development machine, not CI
running on an unrelated distro.

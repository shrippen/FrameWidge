# Review guide

Every PR is reviewed before it is merged (rule in `agent.md`, taken over
from lmix and Kante): by PR-Agent (owner, 22.10.2026); a new Claude agent
checks the **Wichtig** of earlier rounds, and reviews when PR-Agent fails.
The reviewer knows nothing of the session that wrote the change: it gets the
PR's intent, its diff and the repository, and this file. The owner does not
read code; this review is the second reader.

## What failure looks like here

FrameWidge drives the fans and the charging of a laptop as root. A bug that
matters is one that harms the machine or the battery, leaks control to
someone who should not have it, or leaves the user without a working widget:

- **Cooling:** a fan stays at a fixed duty without its control loop (no
  `--restore-fan` on stop or crash), a curve gives a lower duty than its
  points say, a sensor name no longer matches so a curve follows the wrong
  or a stale temperature, two programs drive the fans at once.
- **Battery:** a charge limit or rate is written that was not configured,
  or one that was configured is not kept (the EC forgets it).
- **Access:** a change of settings without polkit on the system bus, a
  D-Bus policy that lets anyone but root own the name, input from D-Bus
  reaching `framework_tool` or a file path unchecked.
- **Widget:** the popup or the tray breaks in Plasma (QML errors, a page
  that never leaves "loading", a config patch the service rejects so a
  control silently does nothing), German strings missing.
- **Upgrade:** a user of the last release loses settings (fan curve,
  presets, charge limit) or the installer leaves a broken state; the
  install one-liner on `main` must work for the release it installs.
- **Lies:** README, DESIGN, CHANGELOG, the landing page or comments that say
  something the code does not do.

## What to check in particular

- Service (`service/`): every path that sets a fan duty also has a way
  back to the EC's own curve; `SetConfig` validates before it saves; no
  blocking call (process, file) inside an async D-Bus method without
  `blocking::unblock`.
- Widget: calls go through `js/Api.js`; a patch matches `Config` in
  `service/src/config.rs` (field names, types); Kante styles use Kante
  elements (rule in `agent.md`).
- Root cause on bug fixes: does the fix remove the cause, or hide one case
  of it? Is there a test that failed before the fix?
- Tests: is the new behaviour tested where it can be (`cargo test` in
  `service/`, `tests/run_all.sh`)? Say what is only verified on a Framework
  laptop as root later.

## Skip

- `Cargo.lock`, `demo/world.json` (a copy from shrippen.github.io),
  `package/contents/locale/` (compiled), `package/contents/ui/Kante*`
  (vendored), `dist/`, screenshots and images.
- Formatting and style that `cargo fmt`, `clippy` and `qmllint` already
  enforce.

## How to report

- Every finding names file and line and the concrete input or state that
  goes wrong. No guess without evidence; if unsure, say so.
- Each finding gets one label: **Wichtig** (a bug from the list above,
  must be fixed or answered before the merge), **Kleinigkeit** (optional,
  at most five) or **Bestand** (the bug was there before this PR; not
  blocking).
- The report starts with the count, e.g. "2 Wichtig, 1 Kleinigkeit" (the
  session puts the heading above it). The count of **Wichtig** holds every
  one still open, also from an earlier round, e.g. "1 Wichtig (offen aus
  Runde 1)". Only when none is open it says plainly: "Nichts zu beheben."
- In a later round: say for each open **Wichtig** of the last round whether
  it is fixed, or whether its answer is accepted, with the reason. PR-Agent
  sees no earlier round: it reports only its own findings with their labels,
  and a new Claude agent closes the open ones (`agent.md`).
- Findings in German, code names as they are.

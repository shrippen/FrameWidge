# Demo (internal)

Internal tool for automated screenshots, not part of any release. Uses the shared demo world of all shrippen projects (shrippen.github.io/demo).

`demo/start.sh` opens the widget in plasmoidviewer against `demo/backend.py`, a stand-in for
framewidged (the FrameWidge service) with the editing laptop of Studio Weber, the demo world shared by all shrippen
projects (`demo/world.json`, copied from `shrippen.github.io/demo`): a render job heats the APU, the
fan runs on a curve, the battery stops at 80 %. It runs on a private D-Bus that stands in for the system
bus (`DBUS_SYSTEM_BUS_ADDRESS`). No Framework hardware needed; the installed widget and a running
framewidged are not touched. `demo/shots.sh` renders the landing-page
screenshots offscreen (`demo/shots.json`, run by `shrippen.github.io/demo/tools/screenshots.py`).

#!/usr/bin/env python3
"""Stand-in for framewidged (service/) on D-Bus, for the widget's tests and the demo.

Serves io.github.shrippen.FrameWidge1 with the replies the widget reads (JSON strings, see
DESIGN.md) on the bus that DBUS_SYSTEM_BUS_ADDRESS names: tests/run_unit_tests.sh and the demo
start a private dbus-daemon and point the "system bus" of the mock and the widget at it, so the
real system bus and a running framewidged are never touched. Needs PyGObject (Gio) only.

A second, test-only interface io.github.shrippen.FrameWidge.Mock has:
  Requests() -> JSON array of every call so far, each {"member", "args"}, in order.
               Used by tests to assert how many calls a debounced UI interaction produced.
  Reset()    -> clears the request log and resets the config to its initial defaults.

Prints "READY" once the name is owned.
"""

import copy
import json
import sys
import time

from gi.repository import Gio, GLib

BUS_NAME = "io.github.shrippen.FrameWidge"
OBJECT_PATH = "/io/github/shrippen/FrameWidge"
INTERFACE = "io.github.shrippen.FrameWidge1"
MOCK_INTERFACE = "io.github.shrippen.FrameWidge.Mock"

INTROSPECTION = f"""
<node>
  <interface name="{INTERFACE}">
    <method name="Health"><arg type="s" direction="out"/></method>
    <method name="Thermal"><arg type="s" direction="out"/></method>
    <method name="ThermalHistory"><arg type="s" direction="out"/></method>
    <method name="Power"><arg type="s" direction="out"/></method>
    <method name="SetPowerProfile"><arg name="profile" type="s" direction="in"/></method>
    <method name="Versions"><arg type="s" direction="out"/></method>
    <method name="System"><arg type="s" direction="out"/></method>
    <method name="Config"><arg type="s" direction="out"/></method>
    <method name="SetConfig"><arg name="patch" type="s" direction="in"/><arg type="s" direction="out"/></method>
    <method name="Logs"><arg type="s" direction="out"/></method>
  </interface>
  <interface name="{MOCK_INTERFACE}">
    <method name="Requests"><arg type="s" direction="out"/></method>
    <method name="Reset"/>
    <method name="Shots"><arg type="s" direction="out"/></method>
  </interface>
</node>
"""

INITIAL_CONFIG = {
    "fan": {
        "mode": "disabled",
        "manual": {"duty_pct": 50},
        "curve": {
            "points": [[40, 0], [60, 40], [75, 80], [85, 100]],
            "hysteresis_c": 2,
            "rate_limit_pct_per_step": 100,
            "poll_ms": 2000,
            "sensors": []
        },
        "overrides": [],
        "calibration": None,
        "presets": []
    },
    "battery": {
        "charge_limit_max_pct": {"enabled": False, "value": 100},
        "charge_rate_c": {"enabled": False, "value": 1.0},
        "charge_rate_soc_threshold_pct": None
    },
    "telemetry": {"poll_ms": 2000, "retain_seconds": 1800}
}

THERMAL = {
    "temps": {"CPU": 55, "GPU": 48},
    "fans": [{"name": "Fan 1", "rpm": 2200}]
}

POWER = {
    "battery": {
        "percentage": 78, "ac_present": True, "charging": True,
        "present_rate_ma": 1500, "present_voltage_mv": 12000,
        "design_capacity_mah": 4000, "last_full_charge_capacity_mah": 3600,
        "cycle_count": 42, "charge_limit_max_pct": 100
    },
    "profile": {"active": "balanced", "available": ["power-saver", "balanced", "performance"]}
}

SYSTEM = {"cpu": "AMD Ryzen 7 7840U", "memory_total_mb": 32768, "os": "Fedora Linux 44", "dgpu": None}
VERSIONS = {"uefi_version": "03.05", "mainboard_type": "FRANBMCP07", "tool_version": "0.5.0"}
LOGS_TEXT = "mock backend started\nno warnings\n"
# Screenshot plan for the demo (demo/backend.py sets it).
SHOTS = None


def thermal_history():
    # SensorsPage.qml filters history samples by `Date.now() - windowSeconds*1000`,
    # so timestamps need to be close to "now" for tests to see any data at all.
    now_ms = int(time.time() * 1000)
    return [
        {"ts_ms": now_ms - 20000, "temps": {"CPU": 50, "GPU": 45}},
        {"ts_ms": now_ms - 10000, "temps": {"CPU": 55, "GPU": 47}},
        {"ts_ms": now_ms, "temps": {"CPU": 60, "GPU": 49}},
    ]


def merge(dst, src):
    for key, value in src.items():
        if isinstance(value, dict) and isinstance(dst.get(key), dict):
            merge(dst[key], value)
        else:
            dst[key] = value
    return dst


class State:
    def __init__(self):
        self.reset()

    def reset(self):
        self.config = copy.deepcopy(INITIAL_CONFIG)
        self.power = copy.deepcopy(POWER)
        self.requests = []


STATE = State()


def set_config(patch):
    merge(STATE.config, json.loads(patch))
    return json.dumps(STATE.config)


def set_power_profile(profile):
    if profile not in STATE.power["profile"]["available"]:
        raise ValueError("unknown profile " + profile)
    STATE.power["profile"]["active"] = profile


# member -> function(*string args) -> reply string, or None for no reply value.
# demo/backend.py replaces entries.
HANDLERS = {
    "Health": lambda: json.dumps({"cli_present": True, "service_version": "mock-1.0"}),
    "Thermal": lambda: json.dumps(THERMAL),
    "ThermalHistory": lambda: json.dumps(thermal_history()),
    "Power": lambda: json.dumps(STATE.power),
    "SetPowerProfile": set_power_profile,
    "Versions": lambda: json.dumps(VERSIONS),
    "System": lambda: json.dumps(SYSTEM),
    "Config": lambda: json.dumps(STATE.config),
    "SetConfig": set_config,
    "Logs": lambda: LOGS_TEXT,
}

MOCK_HANDLERS = {
    "Requests": lambda: json.dumps(STATE.requests),
    "Reset": lambda: STATE.reset(),
    "Shots": lambda: json.dumps(SHOTS),
}


def on_call(_conn, _sender, _path, interface, member, params, invocation):
    args = list(params.unpack())
    handlers = HANDLERS if interface == INTERFACE else MOCK_HANDLERS
    if interface == INTERFACE:
        STATE.requests.append({"member": member, "args": args})
    try:
        reply = handlers[member](*args)
    except (KeyError, ValueError) as error:
        invocation.return_dbus_error("org.freedesktop.DBus.Error.InvalidArgs", str(error))
        return
    invocation.return_value(None if reply is None else GLib.Variant("(s)", (reply,)))


def main():
    # Gio's system bus honours DBUS_SYSTEM_BUS_ADDRESS.
    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    node = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION)
    for iface in node.interfaces:
        bus.register_object(OBJECT_PATH, iface, on_call, None, None)

    loop = GLib.MainLoop()
    Gio.bus_own_name_on_connection(bus, BUS_NAME, Gio.BusNameOwnerFlags.NONE,
                                   lambda *_: print("READY", flush=True),
                                   lambda *_: (print("name lost", file=sys.stderr), loop.quit()))
    try:
        loop.run()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()

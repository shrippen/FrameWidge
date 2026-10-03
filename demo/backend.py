#!/usr/bin/env python3
"""Demo stand-in for framework-control: tests/fixtures/mock_backend.py with the laptop of the
shrippen demo world (Studio Weber's editing laptop rendering a rough cut, see demo/world.json).

Temperatures and fan follow a render job that ramps up and down, the history covers the last
half hour, the fan runs on a curve and the battery stops at the charge limit.

  demo/backend.py [port]        prints "PORT <n>" like the mock
  demo/backend.py [port] PLAN   also serves the screenshot plan (JSON file) at /__shots,
                                which contents/ui/ScreenshotRunner.qml reads (see demo/shots.sh)
"""
import json
import math
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "tests" / "fixtures"))
import mock_backend as mock  # noqa: E402

WORLD = json.loads((HERE / "world.json").read_text(encoding="utf-8"))
HW = WORLD["hardware"]
RENDER = HW["render"]
START = time.time()


def load(t):
    """Render load 0..1: a job that started a while ago (world: hardware.render), with small bursts."""
    phase = (t - START + RENDER["started_min"] * 60) / 60.0
    return max(RENDER["floor"], min(1.0, RENDER["base"] + RENDER["swing"] * math.sin(phase / 6.0)
                                    + RENDER["burst"] * math.sin(phase * 1.7)))


def temps(t):
    x = load(t)
    return {name: round(idle + rise * x, 1) for name, (idle, rise) in HW["sensors"].items()}


def fan_rpm(t):
    idle, rise = HW["fan"]["rpm"]
    return int(idle + rise * load(t))


def thermal():
    t = time.time()
    return {"temps": temps(t), "fans": [{"name": HW["fan"]["name"], "rpm": fan_rpm(t)}]}


def history():
    now = time.time()
    return [{"ts_ms": int((now - s) * 1000), "temps": temps(now - s)} for s in range(HW["history_min"] * 60, -1, -10)]


mock.INITIAL_CONFIG["fan"]["mode"] = "curve"
mock.INITIAL_CONFIG["fan"]["curve"]["points"] = HW["fan_curve"]
mock.INITIAL_CONFIG["fan"]["curve"]["sensors"] = [HW["fan"]["sensor"]]
mock.INITIAL_CONFIG["battery"]["charge_limit_max_pct"] = {"enabled": True, "value": HW["charge_limit"]}
for profile in ("ac", "battery"):
    mock.INITIAL_CONFIG["power"][profile]["epp_preference"]["enabled"] = True
mock.INITIAL_CONFIG["power"]["ac"]["tdp_watts"] = {"enabled": True, "value": HW["tdp_watts"]}
mock.STATE.reset()

mock.POWER["battery"].update({
    "percentage": HW["battery_percent"], "ac_present": True, "charging": True,
    "present_rate_ma": HW["charging"]["rate_ma"], "present_voltage_mv": HW["charging"]["voltage_mv"], "cycle_count": HW["cycle_count"],
    "design_capacity_mah": round(HW["design_capacity_mwh"] / HW["nominal_voltage"]),
    "last_full_charge_capacity_mah": round(HW["full_capacity_mwh"] / HW["nominal_voltage"]),
    "charge_limit_max_pct": HW["charge_limit"]})
mock.POWER["power_control"]["current_state"].update({"tdp_limit_watts": HW["tdp_watts"], "epp_preference": HW["epp"]})
mock.SYSTEM.update({"cpu": HW["cpu"], "hostname": WORLD["studio"]["laptop"], "model": HW["model"]})
mock.LOGS_TEXT = "".join(line.replace("{charge_limit}", str(HW["charge_limit"])) + "\n" for line in HW["log"])

PLAN = Path(sys.argv[2]).read_text(encoding="utf-8") if len(sys.argv) > 2 else None
_get = mock.Handler.do_GET


def do_GET(self):
    if self.path == "/api/thermal":
        return self._send_json(thermal())
    if self.path == "/api/thermal/history":
        return self._send_json(history())
    if self.path == "/__shots" and PLAN:
        return self._send_json(json.loads(PLAN))
    return _get(self)


mock.Handler.do_GET = do_GET

if __name__ == "__main__":
    sys.argv = sys.argv[:2]
    mock.main()

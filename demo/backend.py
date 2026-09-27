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
START = time.time()


def load(t):
    """Render load 0..1: a job that started 20 minutes ago, with small bursts."""
    phase = (t - START + 1200) / 60.0
    return max(0.15, min(1.0, 0.55 + 0.35 * math.sin(phase / 6.0) + 0.1 * math.sin(phase * 1.7)))


def temps(t):
    x = load(t)
    return {"APU": round(48 + 38 * x, 1), "CPU": round(46 + 40 * x, 1),
            "Battery": round(31 + 4 * x, 1), "SSD": round(38 + 9 * x, 1)}


def fan_rpm(t):
    return int(1800 + 3600 * load(t))


def thermal():
    t = time.time()
    return {"temps": temps(t), "fans": [{"name": "Fan 1", "rpm": fan_rpm(t)}]}


def history():
    now = time.time()
    return [{"ts_ms": int((now - s) * 1000), "temps": temps(now - s)} for s in range(1800, -1, -10)]


mock.INITIAL_CONFIG["fan"]["mode"] = "curve"
mock.INITIAL_CONFIG["fan"]["curve"]["points"] = HW["fan_curve"]
mock.INITIAL_CONFIG["fan"]["curve"]["sensors"] = ["APU"]
mock.INITIAL_CONFIG["battery"]["charge_limit_max_pct"] = {"enabled": True, "value": HW["charge_limit"]}
for profile in ("ac", "battery"):
    mock.INITIAL_CONFIG["power"][profile]["epp_preference"]["enabled"] = True
mock.INITIAL_CONFIG["power"]["ac"]["tdp_watts"] = {"enabled": True, "value": 28}
mock.STATE.reset()

mock.POWER["battery"].update({
    "percentage": HW["battery_percent"], "ac_present": True, "charging": True,
    "present_rate_ma": 2100, "present_voltage_mv": 16800, "cycle_count": HW["cycle_count"],
    "design_capacity_mah": round(HW["design_capacity_mwh"] / 15.4),
    "last_full_charge_capacity_mah": round(HW["full_capacity_mwh"] / 15.4),
    "charge_limit_max_pct": HW["charge_limit"]})
mock.POWER["power_control"]["current_state"].update({"tdp_limit_watts": 28, "epp_preference": "balance_performance"})
mock.SYSTEM.update({"cpu": HW["cpu"], "hostname": WORLD["studio"]["laptop"], "model": HW["model"]})
mock.LOGS_TEXT = "framework-control demo\nfan curve active (APU)\ncharge limit %d %%\n" % HW["charge_limit"]

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

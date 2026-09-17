#!/usr/bin/env python3
"""Minimal stand-in for the framework-control REST API, used by the
plasmoid's tests instead of a real Framework laptop + backend service.

Stdlib only (no dependencies). Serves the subset of /api/* endpoints the
QML widget actually consumes (see DESIGN.md's API reference table) and
adds two test-only introspection routes:

  GET  /__requests  -> JSON array of every request received so far,
                       each as {"method", "path", "body"} in order.
                       Used by tests to assert how many POSTs a
                       debounced UI interaction actually produced.
  POST /__reset      -> clears the request log and resets /api/config
                       back to its initial defaults.

Usage: mock_backend.py [port]  (default: 0, i.e. pick a free port and
print it as a single line "PORT <n>" on stdout so callers can capture
it without racing on a fixed port.)
"""

import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

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
        "overrides": []
    },
    "power": {
        "ac": {
            "epp_preference": {"enabled": False, "value": "balance_performance"},
            "governor": {"enabled": False, "value": "schedutil"},
            "min_freq_mhz": {"enabled": False, "value": 1000},
            "max_freq_mhz": {"enabled": False, "value": 4000},
            "tdp_watts": {"enabled": False, "value": 75},
            "thermal_limit_c": {"enabled": False, "value": 90}
        },
        "battery": {
            "epp_preference": {"enabled": False, "value": "power"},
            "governor": {"enabled": False, "value": "powersave"},
            "min_freq_mhz": {"enabled": False, "value": 1000},
            "max_freq_mhz": {"enabled": False, "value": 3000},
            "tdp_watts": {"enabled": False, "value": 60},
            "thermal_limit_c": {"enabled": False, "value": 90}
        }
    },
    "battery": {
        "charge_limit_max_pct": {"enabled": False, "value": 100},
        "charge_rate_c": {"enabled": False, "value": 1.0},
        "charge_rate_soc_threshold_pct": None
    },
    "telemetry": {"poll_ms": 2000, "retain_seconds": 1800}
}

THERMAL = {
    "temps": {"CPU": 55.0, "GPU": 48.0},
    "fans": [{"name": "Fan 1", "rpm": 2200}]
}

def _recent_thermal_history():
    # SensorsPage.qml filters history samples by `Date.now() - windowSeconds*1000`,
    # so timestamps need to be close to "now" for tests to see any data at all.
    now_ms = int(time.time() * 1000)
    return [
        {"ts_ms": now_ms - 20000, "temps": {"CPU": 50.0, "GPU": 45.0}},
        {"ts_ms": now_ms - 10000, "temps": {"CPU": 55.0, "GPU": 47.0}},
        {"ts_ms": now_ms, "temps": {"CPU": 60.0, "GPU": 49.0}},
    ]

POWER = {
    "power_control": {
        "capabilities": {
            "supports_epp": True,
            "supports_governor": True,
            "supports_frequency_limits": True,
            "supports_tdp": True,
            "supports_thermal": True,
            "available_epp_preferences": ["power", "balance_power", "balance_performance", "performance"],
            "available_governors": ["powersave", "performance", "schedutil"],
            "tdp_min_watts": 5, "tdp_max_watts": 120,
            "frequency_min_mhz": 400, "frequency_max_mhz": 6000
        },
        "current_state": {
            "tdp_limit_watts": 75, "thermal_limit_c": 90,
            "epp_preference": "balance_performance", "governor": "schedutil",
            "min_freq_mhz": 1000, "max_freq_mhz": 4000
        }
    },
    "battery": {
        "percentage": 78, "ac_present": True, "charging": True,
        "present_rate_ma": 1500, "present_voltage_mv": 12000,
        "design_capacity_mah": 4000, "last_full_charge_capacity_mah": 3600,
        "cycle_count": 42, "charge_limit_max_pct": 100
    }
}

SYSTEM = {"cpu": "AMD Ryzen 7 7840U", "memory_total_mb": 32768, "os": "Fedora Linux 44"}
VERSIONS = {"uefi_version": "03.05", "mainboard_type": "FRANBMCP07", "tool_version": "0.5.0"}
LOGS_TEXT = "mock backend started\nno warnings\n"


def merge(dst, src):
    for key, value in src.items():
        if isinstance(value, dict) and isinstance(dst.get(key), dict):
            merge(dst[key], value)
        else:
            dst[key] = value
    return dst


class State:
    def __init__(self):
        self.lock = threading.Lock()
        self.config = json.loads(json.dumps(INITIAL_CONFIG))
        self.requests = []

    def reset(self):
        with self.lock:
            self.config = json.loads(json.dumps(INITIAL_CONFIG))
            self.requests = []


STATE = State()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # keep test output quiet; use /__requests to inspect traffic

    def _send_json(self, payload, status=200):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_text(self, text, status=200):
        body = text.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json_body(self):
        length = int(self.headers.get("Content-Length", 0))
        if length == 0:
            return {}
        raw = self.rfile.read(length)
        return json.loads(raw.decode("utf-8")) if raw else {}

    def _record(self, body):
        with STATE.lock:
            STATE.requests.append({"method": self.command, "path": self.path, "body": body})

    def do_GET(self):
        self._record(None)
        if self.path == "/api/health":
            return self._send_json({"cli_present": True, "service_version": "mock-1.0"})
        if self.path == "/api/thermal":
            return self._send_json(THERMAL)
        if self.path == "/api/thermal/history":
            return self._send_json(_recent_thermal_history())
        if self.path == "/api/power":
            return self._send_json(POWER)
        if self.path == "/api/config":
            with STATE.lock:
                return self._send_json(STATE.config)
        if self.path == "/api/system":
            return self._send_json(SYSTEM)
        if self.path == "/api/versions":
            return self._send_json(VERSIONS)
        if self.path == "/api/logs":
            return self._send_text(LOGS_TEXT)
        if self.path == "/__requests":
            with STATE.lock:
                return self._send_json(STATE.requests)
        self.send_response(404)
        self.end_headers()

    def do_POST(self):
        body = self._read_json_body()
        self._record(body)
        if self.path == "/api/config":
            with STATE.lock:
                merge(STATE.config, body)
                return self._send_json(STATE.config)
        if self.path == "/__reset":
            STATE.reset()
            return self._send_json({"ok": True})
        self.send_response(404)
        self.end_headers()


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print("PORT %d" % server.server_address[1], flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()

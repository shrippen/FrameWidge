//! Runs the real binary on a private D-Bus (`--session`, no polkit) with a
//! fake `framework_tool` (a shell script that logs its arguments and prints
//! recorded output), a fake sysfs tree and a fake power-profiles-daemon.

use serde_json::{json, Value};
use std::collections::HashMap;
use std::fs;
use std::io::{BufRead, BufReader};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};
use zbus::blocking::Connection;
use zbus::zvariant::OwnedValue;

const BUS_NAME: &str = "io.github.shrippen.FrameWidge";
const OBJECT_PATH: &str = "/io/github/shrippen/FrameWidge";
const INTERFACE: &str = "io.github.shrippen.FrameWidge1";

const FAKE_TOOL: &str = r#"#!/bin/sh
echo "$*" >> "$(dirname "$0")/calls.log"
case "$1" in
  --thermal) printf '  F75303_CPU:   38 C\n  APU:          64 C\n  Fan Speed:  1800 RPM\n' ;;
  --charge-limit) [ -z "$2" ] && printf 'Minimum 0%%, Maximum 80%%\n' ;;
  --versions) printf 'Tool Version:     0.6.5\nUEFI BIOS\n  Version:        03.18\n' ;;
esac
exit 0
"#;

#[derive(Clone, Copy, PartialEq)]
enum Tool {
    Fake,
    Missing,
}

#[derive(Clone, Copy, PartialEq)]
enum Hwmon {
    EcDriver,
    /// Older kernel: temperatures only through framework_tool.
    None,
}

struct Setup<'a> {
    name: &'a str,
    legacy: Option<&'a str>,
    tool: Tool,
    hwmon: Hwmon,
}

impl Default for Setup<'_> {
    fn default() -> Self {
        Setup {
            name: "default",
            legacy: None,
            tool: Tool::Fake,
            hwmon: Hwmon::EcDriver,
        }
    }
}

struct Service {
    dir: PathBuf,
    bus: Child,
    address: String,
    service: Child,
    conn: Connection,
}

impl Drop for Service {
    fn drop(&mut self) {
        for child in [&mut self.service, &mut self.bus] {
            let _ = child.kill();
            let _ = child.wait();
        }
        let _ = fs::remove_dir_all(&self.dir);
    }
}

impl Service {
    fn start(setup: Setup) -> Service {
        let dir = std::env::temp_dir().join(format!(
            "framewidged-it-{}-{}",
            setup.name,
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();

        let tool = match setup.tool {
            Tool::Fake => fake_tool(&dir),
            Tool::Missing => dir.join("missing"),
        };
        fake_sysfs(&dir.join("sys"), setup.hwmon);
        let legacy = dir.join("legacy.json");
        if let Some(text) = setup.legacy {
            fs::write(&legacy, text).unwrap();
        }

        let (bus, address) = private_bus();
        let service = Command::new(env!("CARGO_BIN_EXE_framewidged"))
            .arg("--session")
            .arg("--state-dir")
            .arg(dir.join("state"))
            .arg("--framework-tool")
            .arg(&tool)
            .arg("--legacy-config")
            .arg(&legacy)
            .arg("--sysfs")
            .arg(dir.join("sys"))
            .env("DBUS_SESSION_BUS_ADDRESS", &address)
            .stderr(Stdio::null())
            .spawn()
            .unwrap();
        let conn = connect(&address);

        let s = Service {
            dir,
            bus,
            address,
            service,
            conn,
        };
        s.wait_until(|| s.call("Health", &()).is_ok());
        s
    }

    fn call<B>(&self, method: &str, body: &B) -> Result<String, String>
    where
        B: serde::Serialize + zbus::zvariant::DynamicType,
    {
        let reply = self
            .conn
            .call_method(Some(BUS_NAME), OBJECT_PATH, Some(INTERFACE), method, body)
            .map_err(|e| e.to_string())?;
        let body = reply.body();
        if body.signature().to_string().is_empty() {
            return Ok(String::new());
        }
        body.deserialize::<String>().map_err(|e| e.to_string())
    }

    fn get(&self, method: &str) -> Value {
        serde_json::from_str(&self.call(method, &()).unwrap()).unwrap()
    }

    fn set_config(&self, patch: Value) -> Result<Value, String> {
        self.call("SetConfig", &(patch.to_string(),))
            .map(|text| serde_json::from_str(&text).unwrap())
    }

    fn called(&self, line: &str) -> bool {
        self.calls().iter().any(|c| c == line)
    }

    fn calls(&self) -> Vec<String> {
        fs::read_to_string(self.dir.join("calls.log"))
            .unwrap_or_default()
            .lines()
            .map(str::to_string)
            .collect()
    }

    fn sys(&self, rel: &str, value: &str) {
        fs::write(self.dir.join("sys").join(rel), format!("{value}\n")).unwrap();
    }

    /// power-profiles-daemon on this test's bus, until the returned connection drops.
    fn serve_profiles(&self) -> Connection {
        let daemon = FakeProfiles {
            active: "balanced".into(),
        };
        zbus::blocking::connection::Builder::address(self.address.as_str())
            .and_then(|b| b.name("org.freedesktop.UPower.PowerProfiles"))
            .and_then(|b| b.serve_at("/org/freedesktop/UPower/PowerProfiles", daemon))
            .and_then(|b| b.build())
            .unwrap()
    }

    fn wait_until(&self, done: impl Fn() -> bool) {
        let deadline = Instant::now() + Duration::from_secs(10);
        while !done() {
            assert!(Instant::now() < deadline, "timed out");
            thread::sleep(Duration::from_millis(50));
        }
    }
}

/// A dbus-daemon of its own; returns it and its address.
fn private_bus() -> (Child, String) {
    let mut bus = Command::new("dbus-daemon")
        .args(["--session", "--nofork", "--print-address=1"])
        .arg(format!(
            "--address=unix:tmpdir={}",
            std::env::temp_dir().display()
        ))
        .stdout(Stdio::piped())
        .spawn()
        .expect("dbus-daemon");
    let mut line = String::new();
    BufReader::new(bus.stdout.take().unwrap())
        .read_line(&mut line)
        .unwrap();
    (bus, line.trim().to_string())
}

fn connect(address: &str) -> Connection {
    zbus::blocking::connection::Builder::address(address)
        .and_then(|b| b.build())
        .unwrap()
}

fn fake_tool(dir: &Path) -> PathBuf {
    let tool = dir.join("framework_tool");
    fs::write(&tool, FAKE_TOOL).unwrap();
    fs::set_permissions(&tool, fs::Permissions::from_mode(0o755)).unwrap();
    tool
}

fn fake_sysfs(root: &Path, hwmon: Hwmon) {
    let write = |rel: &str, value: &str| {
        let path = root.join(rel);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, format!("{value}\n")).unwrap();
    };
    if hwmon == Hwmon::EcDriver {
        write("class/hwmon/hwmon11/name", "cros_ec");
        write("class/hwmon/hwmon11/temp1_label", "cpu_f75303@4d");
        write("class/hwmon/hwmon11/temp1_input", "38000");
        write("class/hwmon/hwmon11/temp2_label", "cpu@4c");
        write("class/hwmon/hwmon11/temp2_input", "71000");
        write("class/hwmon/hwmon11/fan1_input", "2200");
    }
    write("class/power_supply/ACAD/type", "Mains");
    write("class/power_supply/ACAD/online", "1");
    write("class/power_supply/BAT1/type", "Battery");
    write("class/power_supply/BAT1/present", "1");
    write("class/power_supply/BAT1/status", "Charging");
    write("class/power_supply/BAT1/capacity", "77");
    write("class/power_supply/BAT1/cycle_count", "162");
}

struct FakeProfiles {
    active: String,
}

#[zbus::interface(name = "org.freedesktop.UPower.PowerProfiles")]
impl FakeProfiles {
    #[zbus(property)]
    fn active_profile(&self) -> String {
        self.active.clone()
    }

    #[zbus(property)]
    fn set_active_profile(&mut self, profile: String) {
        self.active = profile;
    }

    #[zbus(property)]
    fn profiles(&self) -> Vec<HashMap<String, OwnedValue>> {
        ["power-saver", "balanced", "performance"]
            .iter()
            .map(|p| {
                HashMap::from([(
                    "Profile".to_string(),
                    OwnedValue::from(zbus::zvariant::Str::from(*p)),
                )])
            })
            .collect()
    }
}

#[test]
fn serves_what_the_widget_reads() {
    let s = Service::start(Setup::default());

    assert_eq!(s.get("Health")["cli_present"], true);

    let thermal = s.get("Thermal");
    assert_eq!(thermal["temps"]["cpu@4c"], 71);
    assert_eq!(thermal["fans"][0]["rpm"], 2200);

    let power = s.get("Power");
    assert_eq!(power["battery"]["ac_present"], true);
    assert_eq!(power["battery"]["percentage"], 77);
    assert_eq!(power["battery"]["cycle_count"], 162);
    assert_eq!(power["battery"]["charge_limit_max_pct"], 80);
    assert_eq!(
        power["profile"],
        Value::Null,
        "no profile daemon on this bus"
    );

    assert_eq!(s.get("Versions")["uefi_version"], "03.18");
    assert_eq!(s.get("Config")["fan"]["mode"], "disabled");
    assert!(s.get("System")["memory_total_mb"].as_u64().unwrap() > 0);

    s.wait_until(|| !s.get("ThermalHistory").as_array().unwrap().is_empty());
    assert!(!s.called("--thermal"), "sysfs, not framework_tool");
}

#[test]
fn reads_temperatures_through_framework_tool_without_ec_driver() {
    let s = Service::start(Setup {
        name: "nohwmon",
        hwmon: Hwmon::None,
        ..Setup::default()
    });
    let thermal = s.get("Thermal");
    assert_eq!(thermal["temps"]["cpu@4c"], 64, "APU under its hwmon name");
    assert_eq!(thermal["fans"][0]["rpm"], 1800);
}

#[test]
fn manual_duty_and_back_to_auto() {
    let s = Service::start(Setup {
        name: "fan",
        ..Setup::default()
    });
    s.wait_until(|| s.called("--autofanctrl"));

    let cfg = s
        .set_config(json!({ "fan": { "mode": "manual", "manual": { "duty_pct": 35 } } }))
        .unwrap();
    assert_eq!(cfg["fan"]["manual"]["duty_pct"], 35);
    s.wait_until(|| s.called("--fansetduty 35"));

    s.set_config(json!({ "fan": { "mode": "disabled" } }))
        .unwrap();
    s.wait_until(|| s.calls().iter().filter(|c| *c == "--autofanctrl").count() == 2);

    let saved = fs::read_to_string(s.dir.join("state/config.json")).unwrap();
    let saved: Value = serde_json::from_str(&saved).unwrap();
    assert_eq!(saved["fan"]["manual"]["duty_pct"], 35);
}

#[test]
fn curve_follows_the_hottest_selected_sensor() {
    let s = Service::start(Setup {
        name: "curve",
        ..Setup::default()
    });
    // "APU" is the old name of cpu@4c (71 °C): 40..80 °C -> 20..60 % gives 51 %.
    let patch = json!({ "fan": { "mode": "curve",
        "curve": { "points": [[40, 20], [80, 60]], "sensors": ["APU"], "poll_ms": 200 } } });
    let cfg = s.set_config(patch).unwrap();
    assert_eq!(cfg["fan"]["curve"]["sensors"], json!(["cpu@4c"]));
    s.wait_until(|| s.called("--fansetduty 51"));
}

#[test]
fn preset_switches_with_the_power_source() {
    let s = Service::start(Setup {
        name: "preset",
        ..Setup::default()
    });
    let quiet = json!({ "name": "Quiet", "power_source": "battery",
        "curve": { "points": [[40, 10], [80, 30]], "poll_ms": 200 } });
    s.set_config(json!({ "fan": { "presets": [quiet] } }))
        .unwrap();
    thread::sleep(Duration::from_millis(300));
    assert_eq!(
        s.get("Config")["fan"]["mode"],
        "disabled",
        "no switch without a change"
    );

    s.sys("class/power_supply/ACAD/online", "0");
    s.wait_until(|| s.get("Config")["fan"]["mode"] == "curve");
    // 71 °C on 40..80 °C -> 10..30 %: 26 %.
    s.wait_until(|| s.called("--fansetduty 26"));
}

#[test]
fn charge_limit_is_written() {
    let s = Service::start(Setup {
        name: "battery",
        ..Setup::default()
    });
    s.set_config(
        json!({ "battery": { "charge_limit_max_pct": { "enabled": true, "value": 85 } } }),
    )
    .unwrap();
    s.wait_until(|| s.called("--charge-limit 85"));
}

#[test]
fn power_profile_goes_to_the_profile_daemon() {
    let s = Service::start(Setup {
        name: "profiles",
        ..Setup::default()
    });
    let _daemon = s.serve_profiles();

    let power = s.get("Power");
    assert_eq!(power["profile"]["active"], "balanced");
    assert_eq!(
        power["profile"]["available"],
        json!(["power-saver", "balanced", "performance"])
    );

    s.call("SetPowerProfile", &("performance",)).unwrap();
    assert_eq!(s.get("Power")["profile"]["active"], "performance");
    assert!(s.call("SetPowerProfile", &("turbo",)).is_err());
}

#[test]
fn rejects_bad_patches() {
    let s = Service::start(Setup {
        name: "reject",
        ..Setup::default()
    });
    let err = s
        .set_config(json!({ "fan": { "mode": "turbo" } }))
        .unwrap_err();
    assert!(err.contains("InvalidArgs"), "{err}");
    assert!(s.call("SetConfig", &("not json",)).is_err());
    assert_eq!(s.get("Config")["fan"]["mode"], "disabled");
}

#[test]
fn takes_over_framework_control_settings() {
    let legacy = r#"{"fan":{"active_profile":"default","profiles":[{"id":"default","mode":"manual","manual":{"duty_pct":64}}]},"version":1}"#;
    let s = Service::start(Setup {
        name: "import",
        legacy: Some(legacy),
        ..Setup::default()
    });
    assert_eq!(s.get("Config")["fan"]["manual"]["duty_pct"], 64);
    s.wait_until(|| s.called("--fansetduty 64"));
}

#[test]
fn without_framework_tool_only_dbus_runs() {
    let s = Service::start(Setup {
        name: "notool",
        tool: Tool::Missing,
        hwmon: Hwmon::None,
        ..Setup::default()
    });
    assert_eq!(s.get("Health")["cli_present"], false);
    assert!(s.call("Thermal", &()).is_err());
    assert_eq!(s.get("Config")["fan"]["mode"], "disabled");
}

#[test]
fn restore_fan_hands_control_back() {
    let dir = std::env::temp_dir().join(format!("framewidged-it-restore-{}", std::process::id()));
    fs::create_dir_all(&dir).unwrap();
    let tool = fake_tool(&dir);

    let status = Command::new(env!("CARGO_BIN_EXE_framewidged"))
        .arg("--restore-fan")
        .arg("--framework-tool")
        .arg(&tool)
        .status()
        .unwrap();
    assert!(status.success());
    let log = fs::read_to_string(dir.join("calls.log")).unwrap();
    assert_eq!(log.trim(), "--autofanctrl");
    let _ = fs::remove_dir_all(&dir);
}

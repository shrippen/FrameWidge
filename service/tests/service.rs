//! Runs the real binary against a fake `framework_tool` (a shell script
//! that logs its arguments and prints recorded output) and fake sysfs.

use std::fs;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

const FAKE_TOOL: &str = r#"#!/bin/sh
echo "$*" >> "$(dirname "$0")/calls.log"
case "$1" in
  --thermal) printf '  F75303_CPU:   38 C\n  APU:          71 C\n  Fan Speed:  2200 RPM\n' ;;
  --power) printf '  AC is:            connected\n  Battery is:       connected\n  Charge level:     77%%\n  Cycle Count:      162\n  Battery charging\n' ;;
  --charge-limit) [ -z "$2" ] && printf 'Minimum 0%%, Maximum 80%%\n' ;;
  --versions) printf 'Tool Version:     0.6.5\nUEFI BIOS\n  Version:        03.18\n' ;;
esac
exit 0
"#;

struct Service {
    child: Child,
    dir: PathBuf,
    port: u16,
}

impl Drop for Service {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        let _ = fs::remove_dir_all(&self.dir);
    }
}

impl Service {
    fn start(name: &str, legacy: Option<&str>) -> Service {
        Service::start_with(name, legacy, Tool::Fake)
    }

    fn start_with(name: &str, legacy: Option<&str>, tool: Tool) -> Service {
        let dir =
            std::env::temp_dir().join(format!("framewidged-it-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();

        let tool = match tool {
            Tool::Fake => fake_tool(&dir),
            Tool::Missing => dir.join("missing"),
        };

        let cpu = dir.join("sys/cpu0/cpufreq");
        fs::create_dir_all(&cpu).unwrap();
        for (file, value) in [
            ("scaling_governor", "powersave"),
            ("scaling_available_governors", "performance powersave"),
            ("cpuinfo_min_freq", "400000"),
            ("cpuinfo_max_freq", "5100000"),
            ("scaling_min_freq", "400000"),
            ("scaling_max_freq", "5100000"),
            ("scaling_cur_freq", "1200000"),
        ] {
            fs::write(cpu.join(file), value).unwrap();
        }

        let legacy_path = dir.join("legacy.json");
        if let Some(text) = legacy {
            fs::write(&legacy_path, text).unwrap();
        }

        let port = free_port();
        let child = Command::new(env!("CARGO_BIN_EXE_framewidged"))
            .args(["--port", &port.to_string()])
            .arg("--state-dir")
            .arg(dir.join("state"))
            .arg("--framework-tool")
            .arg(&tool)
            .arg("--legacy-config")
            .arg(&legacy_path)
            .arg("--sysfs-cpu")
            .arg(dir.join("sys"))
            .stderr(Stdio::null())
            .spawn()
            .unwrap();

        let service = Service { child, dir, port };
        service.wait_until(|| service.get("/api/health").0 == 200);
        service
    }

    fn get(&self, path: &str) -> (u16, String) {
        self.request(&format!(
            "GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{}\r\nConnection: close\r\n\r\n",
            self.port
        ))
    }

    fn post(&self, path: &str, content_type: &str, body: &str) -> (u16, String) {
        self.request(&format!(
            "POST {path} HTTP/1.1\r\nHost: 127.0.0.1:{}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            self.port,
            body.len()
        ))
    }

    fn request(&self, raw: &str) -> (u16, String) {
        let Ok(mut s) = TcpStream::connect(("127.0.0.1", self.port)) else {
            return (0, String::new());
        };
        s.write_all(raw.as_bytes()).unwrap();
        let mut out = String::new();
        s.read_to_string(&mut out).unwrap();

        let status = out
            .split_whitespace()
            .nth(1)
            .and_then(|c| c.parse().ok())
            .unwrap_or(0);
        let body = out
            .split_once("\r\n\r\n")
            .map(|(_, b)| b.to_string())
            .unwrap_or_default();
        (status, body)
    }

    fn calls(&self) -> Vec<String> {
        fs::read_to_string(self.dir.join("calls.log"))
            .unwrap_or_default()
            .lines()
            .map(str::to_string)
            .collect()
    }

    fn wait_until(&self, done: impl Fn() -> bool) {
        let deadline = Instant::now() + Duration::from_secs(10);
        while !done() {
            assert!(Instant::now() < deadline, "timed out");
            thread::sleep(Duration::from_millis(50));
        }
    }
}

enum Tool {
    Fake,
    Missing,
}

fn fake_tool(dir: &Path) -> PathBuf {
    let tool = dir.join("framework_tool");
    fs::write(&tool, FAKE_TOOL).unwrap();
    fs::set_permissions(&tool, fs::Permissions::from_mode(0o755)).unwrap();
    tool
}

fn free_port() -> u16 {
    TcpListener::bind("127.0.0.1:0")
        .unwrap()
        .local_addr()
        .unwrap()
        .port()
}

fn json(body: &str) -> serde_json::Value {
    serde_json::from_str(body).unwrap()
}

#[test]
fn serves_what_the_widget_reads() {
    let s = Service::start("read", None);

    let health = json(&s.get("/api/health").1);
    assert_eq!(health["cli_present"], true);

    let thermal = json(&s.get("/api/thermal").1);
    assert_eq!(thermal["temps"]["APU"], 71);
    assert_eq!(thermal["fans"][0]["rpm"], 2200);

    let power = json(&s.get("/api/power").1);
    assert_eq!(power["battery"]["ac_present"], true);
    assert_eq!(power["battery"]["percentage"], 77);
    assert_eq!(power["battery"]["charge_limit_max_pct"], 80);
    assert_eq!(
        power["power_control"]["capabilities"]["frequency_max_mhz"],
        5100
    );
    assert_eq!(
        power["power_control"]["current_state"]["governor"],
        "powersave"
    );

    assert_eq!(json(&s.get("/api/versions").1)["uefi_version"], "03.18");
    assert_eq!(json(&s.get("/api/config").1)["fan"]["mode"], "disabled");
    assert!(
        json(&s.get("/api/system").1)["memory_total_mb"]
            .as_u64()
            .unwrap()
            > 0
    );

    s.wait_until(|| {
        !json(&s.get("/api/thermal/history").1)
            .as_array()
            .unwrap()
            .is_empty()
    });
    assert_eq!(s.get("/api/nothing").0, 404);
}

#[test]
fn manual_duty_and_back_to_auto() {
    let s = Service::start("fan", None);
    s.wait_until(|| s.calls().iter().any(|c| c == "--autofanctrl"));

    let (status, body) = s.post(
        "/api/config",
        "application/json",
        r#"{"fan":{"mode":"manual","manual":{"duty_pct":35}}}"#,
    );
    assert_eq!(status, 200);
    assert_eq!(json(&body)["fan"]["manual"]["duty_pct"], 35);
    s.wait_until(|| s.calls().iter().any(|c| c == "--fansetduty 35"));

    s.post(
        "/api/config",
        "application/json",
        r#"{"fan":{"mode":"disabled"}}"#,
    );
    s.wait_until(|| s.calls().iter().filter(|c| *c == "--autofanctrl").count() == 2);

    // Saved across restarts.
    let saved = fs::read_to_string(s.dir.join("state/config.json")).unwrap();
    assert_eq!(json(&saved)["fan"]["manual"]["duty_pct"], 35);
}

#[test]
fn curve_follows_the_hottest_selected_sensor() {
    let s = Service::start("curve", None);
    let patch = r#"{"fan":{"mode":"curve","curve":{"points":[[40,20],[80,60]],"sensors":["APU"],"poll_ms":200}}}"#;
    assert_eq!(s.post("/api/config", "application/json", patch).0, 200);

    // APU 71 °C on 40..80 °C -> 20..60 %: 51 %.
    s.wait_until(|| s.calls().iter().any(|c| c == "--fansetduty 51"));
}

#[test]
fn charge_limit_is_written() {
    let s = Service::start("battery", None);
    let patch = r#"{"battery":{"charge_limit_max_pct":{"enabled":true,"value":85}}}"#;
    assert_eq!(s.post("/api/config", "application/json", patch).0, 200);
    s.wait_until(|| s.calls().iter().any(|c| c == "--charge-limit 85"));
}

#[test]
fn rejects_bad_patches_and_foreign_requests() {
    let s = Service::start("reject", None);

    assert_eq!(
        s.post(
            "/api/config",
            "application/json",
            r#"{"fan":{"mode":"turbo"}}"#
        )
        .0,
        400
    );
    assert_eq!(s.post("/api/config", "application/json", "not json").0, 400);
    // A web page can send text/plain without a CORS preflight.
    assert_eq!(
        s.post("/api/config", "text/plain", r#"{"fan":{"mode":"manual"}}"#)
            .0,
        415
    );
    assert_eq!(json(&s.get("/api/config").1)["fan"]["mode"], "disabled");

    // DNS rebinding: a page's own host name.
    let raw = "GET /api/config HTTP/1.1\r\nHost: evil.example:80\r\nConnection: close\r\n\r\n";
    assert_eq!(s.request(raw).0, 403);
}

#[test]
fn takes_over_framework_control_settings() {
    let legacy = r#"{"fan":{"active_profile":"default","profiles":[{"id":"default","mode":"manual","manual":{"duty_pct":64}}]},"version":1}"#;
    let s = Service::start("import", Some(legacy));
    assert_eq!(
        json(&s.get("/api/config").1)["fan"]["manual"]["duty_pct"],
        64
    );
    s.wait_until(|| s.calls().iter().any(|c| c == "--fansetduty 64"));
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
    assert_eq!(
        fs::read_to_string(log(&dir)).unwrap().trim(),
        "--autofanctrl"
    );
    let _ = fs::remove_dir_all(&dir);
}

fn log(dir: &Path) -> PathBuf {
    dir.join("calls.log")
}

#[test]
fn without_framework_tool_only_the_api_runs() {
    let s = Service::start_with("notool", None, Tool::Missing);
    assert_eq!(json(&s.get("/api/health").1)["cli_present"], false);
    assert_eq!(s.get("/api/thermal").0, 502);
    assert_eq!(s.get("/api/config").0, 200);
}

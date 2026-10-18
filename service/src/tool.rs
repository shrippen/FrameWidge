//! Driver for `framework_tool` (FrameworkComputer/framework-system), the
//! only way this service talks to the embedded controller (EC).
//!
//! One call at a time: the EC serves one host command at a time, and two
//! loops (fan, battery) plus HTTP requests would otherwise interleave.
//! Reads are cached briefly, since every widget poll and every fan step
//! needs the same thermal reading.

use crate::parse::{self, Battery, ChargeLimit, Thermal, Versions};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use std::thread;
use std::time::{Duration, Instant};

const TOOL_NAME: &str = "framework_tool";

/// Where install.sh puts the tool when it is not on PATH.
const INSTALL_DIR: &str = "/usr/local/lib/framewidge";

const CALL_TIMEOUT: Duration = Duration::from_secs(30);
const THERMAL_TTL: Duration = Duration::from_secs(1);
const BATTERY_TTL: Duration = Duration::from_secs(5);
const VERSIONS_TTL: Duration = Duration::from_secs(3600);

/// Which fan a duty applies to.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Fan {
    All,
    Index(u32),
}

struct Cached<T> {
    at: Instant,
    value: T,
}

#[derive(Default)]
struct Cache {
    thermal: Option<Cached<Thermal>>,
    battery: Option<Cached<Battery>>,
    limit: Option<Cached<ChargeLimit>>,
    versions: Option<Cached<Versions>>,
}

pub struct Tool {
    path: Option<PathBuf>,
    cache: Mutex<Cache>,
}

impl Tool {
    /// `explicit` (from --framework-tool) if given, else PATH, then INSTALL_DIR.
    /// A path that is not a file counts as no tool.
    pub fn locate(explicit: Option<PathBuf>) -> Tool {
        let path = match explicit {
            Some(p) => Some(p).filter(|p| p.is_file()),
            None => find_tool(),
        };
        Tool {
            path,
            cache: Mutex::new(Cache::default()),
        }
    }

    pub fn present(&self) -> bool {
        self.path.is_some()
    }

    pub fn thermal(&self) -> Result<Thermal, String> {
        let mut cache = self.lock();
        if let Some(v) = fresh(&cache.thermal, THERMAL_TTL) {
            return Ok(v);
        }
        let value = parse::thermal(&self.run(&["--thermal"])?);
        cache.thermal = Some(Cached {
            at: Instant::now(),
            value: value.clone(),
        });
        Ok(value)
    }

    pub fn battery(&self) -> Result<Battery, String> {
        let mut cache = self.lock();
        if let Some(v) = fresh(&cache.battery, BATTERY_TTL) {
            return Ok(v);
        }
        let value = parse::battery(&self.run(&["--power", "-vv"])?);
        cache.battery = Some(Cached {
            at: Instant::now(),
            value: value.clone(),
        });
        Ok(value)
    }

    pub fn charge_limit(&self) -> Result<ChargeLimit, String> {
        let mut cache = self.lock();
        if let Some(v) = fresh(&cache.limit, BATTERY_TTL) {
            return Ok(v);
        }
        let value = parse::charge_limit(&self.run(&["--charge-limit"])?);
        if value.charge_limit_max_pct.is_none() {
            return Err("charge limit not in framework_tool output".into());
        }
        cache.limit = Some(Cached {
            at: Instant::now(),
            value: value.clone(),
        });
        Ok(value)
    }

    pub fn versions(&self) -> Result<Versions, String> {
        let mut cache = self.lock();
        if let Some(v) = fresh(&cache.versions, VERSIONS_TTL) {
            return Ok(v);
        }
        let value = parse::versions(&self.run(&["--versions"])?);
        cache.versions = Some(Cached {
            at: Instant::now(),
            value: value.clone(),
        });
        Ok(value)
    }

    pub fn set_fan_duty(&self, fan: Fan, pct: u32) -> Result<(), String> {
        let pct = pct.min(100).to_string();
        let index;
        let args: Vec<&str> = match fan {
            Fan::All => vec!["--fansetduty", &pct],
            Fan::Index(i) => {
                index = i.to_string();
                vec!["--fansetduty", &index, &pct]
            }
        };

        let _guard = self.lock();
        self.run(&args).map(drop)
    }

    /// Hands the fans back to the EC's own curve.
    pub fn auto_fan(&self) -> Result<(), String> {
        let _guard = self.lock();
        self.run(&["--autofanctrl"]).map(drop)
    }

    pub fn set_charge_limit(&self, max_pct: u8) -> Result<(), String> {
        let mut cache = self.lock();
        cache.limit = None;
        self.run(&["--charge-limit", &max_pct.to_string()])
            .map(drop)
    }

    /// `rate_c`: charge current as a fraction of capacity (0.05..1.0 C), from `soc_pct` on.
    pub fn set_charge_rate(&self, rate_c: f32, soc_pct: Option<u8>) -> Result<(), String> {
        let rate = format!("{rate_c:.3}");
        let soc = soc_pct.map(|s| s.to_string());
        let mut args = vec!["--charge-rate-limit", rate.as_str()];
        if let Some(s) = &soc {
            args.push(s);
        }

        let _guard = self.lock();
        self.run(&args).map(drop)
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Cache> {
        self.cache.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Callers hold the cache lock, which serialises all EC access.
    fn run(&self, args: &[&str]) -> Result<String, String> {
        let path = self.path.as_ref().ok_or("framework_tool not found")?;
        let child = Command::new(path)
            .args(args)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| format!("{}: {e}", path.display()))?;

        let (status, stdout, stderr) = wait(child, CALL_TIMEOUT)?;
        if !status.success() {
            return Err(format!(
                "framework_tool {}: {status}: {}",
                args.join(" "),
                // One journal line per error.
                stderr.trim().replace('\n', " | ")
            ));
        }
        Ok(stdout)
    }
}

fn fresh<T: Clone>(slot: &Option<Cached<T>>, ttl: Duration) -> Option<T> {
    slot.as_ref()
        .filter(|c| c.at.elapsed() < ttl)
        .map(|c| c.value.clone())
}

fn find_tool() -> Option<PathBuf> {
    let on_path = std::env::var_os("PATH")
        .map(|p| {
            std::env::split_paths(&p)
                .map(|d| d.join(TOOL_NAME))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    on_path
        .into_iter()
        .chain([Path::new(INSTALL_DIR).join(TOOL_NAME)])
        .find(|p| p.is_file())
}

/// Waits for `child`, killing it after `timeout`. Output is read on threads so
/// a full pipe cannot block the child.
fn wait(
    mut child: Child,
    timeout: Duration,
) -> Result<(std::process::ExitStatus, String, String), String> {
    let stdout = drain(child.stdout.take());
    let stderr = drain(child.stderr.take());
    let deadline = Instant::now() + timeout;

    let status = loop {
        if let Some(status) = child.try_wait().map_err(|e| e.to_string())? {
            break status;
        }
        if Instant::now() >= deadline {
            let _ = child.kill();
            let _ = child.wait();
            return Err("framework_tool timed out".into());
        }
        thread::sleep(Duration::from_millis(10));
    };

    let out = stdout.join().unwrap_or_default();
    let err = stderr.join().unwrap_or_default();
    Ok((status, out, err))
}

fn drain<R: Read + Send + 'static>(pipe: Option<R>) -> thread::JoinHandle<String> {
    thread::spawn(move || {
        let mut text = String::new();
        if let Some(mut p) = pipe {
            let mut bytes = Vec::new();
            let _ = p.read_to_end(&mut bytes);
            text = String::from_utf8_lossy(&bytes).into_owned();
        }
        text
    })
}

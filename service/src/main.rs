//! framewidged: the FrameWidge backend service.
//!
//! ```text
//!  Plasma widget ──D-Bus (system bus)──▶ dbus ──▶ App (config, history)
//!                                         │  └──▶ profiles (power-profiles-daemon)
//!                     control loop: fans, charge, history, preset switch
//!                                         │
//!       drivers: sysfs (reads), tool (framework_tool → EC: writes)
//! ```
//!
//! Runs as root (systemd): `framework_tool` needs it for the EC.

mod battery;
mod config;
mod control;
mod dbus;
mod fan;
mod parse;
mod profiles;
mod sensors;
mod sysfs;
mod system;
mod telemetry;
mod tool;

use config::{Config, PowerSource, Store};
use sensors::Thermal;
use serde_json::Value;
use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::{Arc, Mutex, RwLock};
use std::thread;

const DEFAULT_STATE_DIR: &str = "/var/lib/framewidged";

const USAGE: &str = "usage: framewidged [--session] [--state-dir DIR] [--framework-tool PATH]
                   [--legacy-config FILE] [--sysfs DIR]
       framewidged --restore-fan   hand the fans back to the EC and exit
       framewidged --version

  --session   serve on the session bus without polkit (tests, development)";

pub struct App {
    pub tool: tool::Tool,
    sysfs: sysfs::Sysfs,
    history: Mutex<telemetry::History>,
    config: RwLock<Config>,
    store: Store,
}

impl App {
    pub fn config(&self) -> Config {
        self.config
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
    }

    /// Validates, saves, then publishes the patched config.
    pub fn update_config(&self, patch: &Value) -> Result<Config, String> {
        let mut cfg = self.config.write().unwrap_or_else(|e| e.into_inner());
        let next = cfg.patched(patch)?;
        self.store.save(&next)?;
        *cfg = next.clone();
        Ok(next)
    }

    /// Makes the preset tagged with `source` the active curve, if there is one.
    pub fn apply_preset_for(&self, source: PowerSource) {
        let mut cfg = self.config.write().unwrap_or_else(|e| e.into_inner());
        let Some(next) = cfg.with_preset_for(source) else {
            return;
        };
        if let Err(e) = self.store.save(&next) {
            eprintln!("<4>{e}");
        }
        eprintln!("<6>power source {source:?}: preset applied");
        *cfg = next;
    }

    /// From the EC hwmon driver, else from `framework_tool`.
    pub fn thermal(&self) -> Result<Thermal, String> {
        match self.sysfs.thermal() {
            Some(t) => Ok(t),
            None => self.tool.thermal(),
        }
    }

    pub fn battery(&self) -> sysfs::Battery {
        self.sysfs.battery()
    }

    pub fn power_source(&self) -> Option<PowerSource> {
        let on_ac = self.battery().ac_present?;
        Some(if on_ac {
            PowerSource::Ac
        } else {
            PowerSource::Battery
        })
    }

    pub fn record(&self, thermal: &Thermal, retain_seconds: u64) {
        self.history
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .record(thermal, retain_seconds);
    }

    pub fn history(&self) -> Vec<telemetry::Sample> {
        self.history
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .samples()
    }
}

struct Args {
    session: bool,
    state_dir: PathBuf,
    framework_tool: Option<PathBuf>,
    legacy_config: PathBuf,
    sysfs: PathBuf,
    restore_fan: bool,
}

fn main() -> ExitCode {
    let args = match parse_args() {
        Ok(Some(a)) => a,
        Ok(None) => return ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("{e}\n{USAGE}");
            return ExitCode::FAILURE;
        }
    };

    let tool = tool::Tool::locate(args.framework_tool);

    // Run by systemd after the service stopped or crashed (ExecStopPost),
    // so a fan never stays at a fixed duty without its loop.
    if args.restore_fan {
        return match tool.auto_fan() {
            Ok(()) => ExitCode::SUCCESS,
            Err(e) => {
                eprintln!("<3>{e}");
                ExitCode::FAILURE
            }
        };
    }

    let store = Store::new(&args.state_dir);
    let app = Arc::new(App {
        tool,
        sysfs: sysfs::Sysfs::new(&args.sysfs),
        history: Mutex::new(telemetry::History::default()),
        config: RwLock::new(store.load(&args.legacy_config)),
        store,
    });

    let (builder, auth) = if args.session {
        (
            zbus::blocking::connection::Builder::session(),
            dbus::Auth::Open,
        )
    } else {
        (
            zbus::blocking::connection::Builder::system(),
            dbus::Auth::Polkit,
        )
    };
    let service = dbus::Service {
        app: Arc::clone(&app),
        auth,
    };
    let connection = builder
        .and_then(|b| b.name(dbus::BUS_NAME))
        .and_then(|b| b.serve_at(dbus::OBJECT_PATH, service))
        .and_then(|b| b.build());
    let _connection = match connection {
        Ok(c) => c,
        Err(e) => {
            eprintln!("<3>D-Bus {}: {e}", dbus::BUS_NAME);
            return ExitCode::FAILURE;
        }
    };
    eprintln!(
        "<6>framewidged {} on D-Bus as {}",
        env!("CARGO_PKG_VERSION"),
        dbus::BUS_NAME
    );

    // The control loop needs framework_tool to act. Without it only D-Bus
    // runs and reports cli_present: false; the widget explains.
    if !app.tool.present() {
        eprintln!("<4>framework_tool not found; install it and restart the service");
        loop {
            thread::park();
        }
    }
    control::run(&app);
    ExitCode::SUCCESS
}

/// `Ok(None)`: answered (--version, --help), nothing to run.
fn parse_args() -> Result<Option<Args>, String> {
    let mut args = Args {
        session: false,
        state_dir: std::env::var_os("STATE_DIRECTORY")
            .map_or_else(|| DEFAULT_STATE_DIR.into(), PathBuf::from),
        framework_tool: None,
        legacy_config: config::LEGACY_CONFIG.into(),
        sysfs: sysfs::SYSFS.into(),
        restore_fan: false,
    };

    let mut it = std::env::args().skip(1);
    while let Some(flag) = it.next() {
        let mut value = || it.next().ok_or_else(|| format!("{flag} needs a value"));
        match flag.as_str() {
            "--session" => args.session = true,
            "--state-dir" => args.state_dir = value()?.into(),
            "--framework-tool" => args.framework_tool = Some(value()?.into()),
            "--legacy-config" => args.legacy_config = value()?.into(),
            "--sysfs" => args.sysfs = value()?.into(),
            "--restore-fan" => args.restore_fan = true,
            "--version" => {
                println!("framewidged {}", env!("CARGO_PKG_VERSION"));
                return Ok(None);
            }
            "--help" | "-h" => {
                println!("{USAGE}");
                return Ok(None);
            }
            other => return Err(format!("unknown argument {other}")),
        }
    }
    Ok(Some(args))
}

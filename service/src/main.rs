//! framewidged: the FrameWidge backend service.
//!
//! ```text
//!  Plasma widget ──HTTP 127.0.0.1──▶ api ──▶ App (config, history)
//!                                             │
//!            loops: fan, battery, power, telemetry
//!                                             │
//!                  drivers: tool (framework_tool → EC), cpufreq (sysfs)
//! ```
//!
//! Runs as root (systemd): the EC and cpufreq are not writable otherwise.

mod api;
mod battery;
mod config;
mod cpufreq;
mod fan;
mod parse;
mod power;
mod system;
mod telemetry;
mod tool;

use config::{Config, Store};
use serde_json::Value;
use std::collections::VecDeque;
use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::{Arc, Mutex, RwLock};
use std::thread;

const DEFAULT_PORT: u16 = 30913;
const DEFAULT_STATE_DIR: &str = "/var/lib/framewidged";

/// A background loop; runs on its own thread for the life of the service.
type Task = fn(Arc<App>);

const USAGE: &str = "usage: framewidged [--port N] [--state-dir DIR] [--framework-tool PATH]
                   [--legacy-config FILE] [--sysfs-cpu DIR]
       framewidged --restore-fan   hand the fans back to the EC and exit
       framewidged --version";

pub struct App {
    pub port: u16,
    pub tool: tool::Tool,
    pub cpufreq: cpufreq::Cpufreq,
    pub history: Mutex<VecDeque<telemetry::Sample>>,
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
}

struct Args {
    port: u16,
    state_dir: PathBuf,
    framework_tool: Option<PathBuf>,
    legacy_config: PathBuf,
    sysfs_cpu: PathBuf,
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

    let server = match tiny_http::Server::http(("127.0.0.1", args.port)) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("<3>127.0.0.1:{}: {e}", args.port);
            return ExitCode::FAILURE;
        }
    };

    let store = Store::new(&args.state_dir);
    let app = Arc::new(App {
        port: args.port,
        tool,
        cpufreq: cpufreq::Cpufreq::new(&args.sysfs_cpu),
        history: Mutex::new(VecDeque::new()),
        config: RwLock::new(store.load(&args.legacy_config)),
        store,
    });

    // Every loop needs framework_tool (power: for the AC state). Without it
    // only the API runs and reports cli_present: false; the widget explains.
    let tasks: &[(&str, Task)] = if app.tool.present() {
        &[
            ("fan", fan::run),
            ("battery", battery::run),
            ("power", power::run),
            ("telemetry", telemetry::run),
        ]
    } else {
        eprintln!("<4>framework_tool not found; install it and restart the service");
        &[]
    };
    for &(name, task) in tasks {
        let app = Arc::clone(&app);
        let spawned = thread::Builder::new()
            .name(name.into())
            .spawn(move || task(app));
        if let Err(e) = spawned {
            eprintln!("<3>{name}: {e}");
            return ExitCode::FAILURE;
        }
    }

    eprintln!(
        "<6>framewidged {} on 127.0.0.1:{}",
        env!("CARGO_PKG_VERSION"),
        args.port
    );
    api::serve(app, server);
    ExitCode::SUCCESS
}

/// `Ok(None)`: answered (--version, --help), nothing to run.
fn parse_args() -> Result<Option<Args>, String> {
    let mut args = Args {
        port: DEFAULT_PORT,
        state_dir: std::env::var_os("STATE_DIRECTORY")
            .map_or_else(|| DEFAULT_STATE_DIR.into(), PathBuf::from),
        framework_tool: None,
        legacy_config: config::LEGACY_CONFIG.into(),
        sysfs_cpu: cpufreq::SYSFS_CPU.into(),
        restore_fan: false,
    };

    let mut it = std::env::args().skip(1);
    while let Some(flag) = it.next() {
        let mut value = || it.next().ok_or_else(|| format!("{flag} needs a value"));
        match flag.as_str() {
            "--port" => args.port = value()?.parse().map_err(|e| format!("--port: {e}"))?,
            "--state-dir" => args.state_dir = value()?.into(),
            "--framework-tool" => args.framework_tool = Some(value()?.into()),
            "--legacy-config" => args.legacy_config = value()?.into(),
            "--sysfs-cpu" => args.sysfs_cpu = value()?.into(),
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

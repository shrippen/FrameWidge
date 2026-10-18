//! Host facts for the widget's System Info page, and the service log.

use serde::Serialize;
use std::fs;
use std::process::Command;

const KB_PER_MB: u64 = 1024;
const LOG_LINES: &str = "500";
pub const UNIT: &str = "framewidged";

#[derive(Debug, Serialize)]
pub struct Info {
    pub cpu: String,
    pub memory_total_mb: u64,
    pub os: String,
    pub dgpu: Option<String>,
}

pub fn info() -> Info {
    let cpuinfo = fs::read_to_string("/proc/cpuinfo").unwrap_or_default();
    let meminfo = fs::read_to_string("/proc/meminfo").unwrap_or_default();
    let os_release = fs::read_to_string("/etc/os-release").unwrap_or_default();

    Info {
        cpu: field(&cpuinfo, "model name", ':').unwrap_or_default(),
        memory_total_mb: field(&meminfo, "MemTotal", ':')
            .and_then(|v| v.split_whitespace().next()?.parse::<u64>().ok())
            .map_or(0, |kb| kb / KB_PER_MB),
        os: field(&os_release, "NAME", '=')
            .map_or_else(|| "Linux".into(), |v| v.trim_matches('"').to_string()),
        dgpu: None,
    }
}

/// Value of the first "key<sep>value" line.
fn field(text: &str, key: &str, sep: char) -> Option<String> {
    text.lines().find_map(|l| {
        let (k, v) = l.split_once(sep)?;
        (k.trim() == key).then(|| v.trim().to_string())
    })
}

/// Last lines of this service's journal.
pub fn logs() -> Result<String, String> {
    let out = Command::new("journalctl")
        .args(["-u", UNIT, "-n", LOG_LINES, "--no-pager"])
        .output()
        .map_err(|e| format!("journalctl: {e}"))?;
    if !out.status.success() {
        return Err(String::from_utf8_lossy(&out.stderr).into_owned());
    }
    Ok(String::from_utf8_lossy(&out.stdout).into_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_fields() {
        assert_eq!(
            field("model name\t: AMD Ryzen 7\n", "model name", ':').as_deref(),
            Some("AMD Ryzen 7")
        );
        assert_eq!(
            field("ID=fedora\nNAME=\"Fedora Linux\"\n", "NAME", '=').as_deref(),
            Some("\"Fedora Linux\"")
        );
        assert_eq!(field("", "NAME", '='), None);
    }
}

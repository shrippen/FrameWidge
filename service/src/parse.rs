//! Parsers for the text output of `framework_tool`.
//!
//! Ported from framework-control by Kemal Ozturk (MIT, see LICENSE):
//! `service/src/cli/framework_tool_parser.rs`. Test samples are real
//! output of Framework 13 and 16 laptops.

use crate::sensors::{self, FanReading, Thermal};
use serde::Serialize;

/// EC fan-speed sentinels: 0xFFFE = stalled (printed as 65534), 0xFFFF = not present.
const EC_FAN_SENTINEL_MIN: u32 = 0xFFFE;

#[derive(Debug, Clone, Default, Serialize)]
pub struct ChargeLimit {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub charge_limit_min_pct: Option<u8>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub charge_limit_max_pct: Option<u8>,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct Versions {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tool_version: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mainboard_type: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mainboard_revision: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub uefi_version: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub uefi_release_date: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ec_build_version: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ec_current_image: Option<String>,
}

/// `--thermal`: "  APU:   62 C" lines are temperatures, "  Fan Speed:  3171 RPM" lines fans.
/// Only used on kernels without the EC hwmon driver (see sysfs.rs).
pub fn thermal(stdout: &str) -> Thermal {
    let mut out = Thermal::default();

    for line in stdout.lines() {
        let l = line.trim();

        if let Some((key, value)) = temperature(l) {
            out.temps.insert(sensors::canonical(&key), value);
            continue;
        }

        if let Some(reading) = fan_line(l, out.fans.len()) {
            out.fans.push(reading);
        }
    }

    out
}

fn temperature(line: &str) -> Option<(String, i32)> {
    let (key, rest) = line.split_once(':')?;
    let c_pos = rest.rfind('C')?;
    let value = rest[..c_pos]
        .split_whitespace()
        .last()?
        .parse::<i32>()
        .ok()?;
    Some((key.trim().to_string(), value))
}

fn fan_line(line: &str, position: usize) -> Option<FanReading> {
    let rpm_pos = line.find("RPM")?;
    let raw: u32 = line[..rpm_pos].split_whitespace().last()?.parse().ok()?;

    // A stalled fan keeps its slot (fan index) but reads 0, not 65534.
    let stalled = raw >= EC_FAN_SENTINEL_MIN || line.contains("Stalled");
    let rpm = if stalled { 0 } else { raw };

    let name = line
        .split_once(':')
        .map(|(n, _)| n.trim())
        .filter(|n| !n.is_empty())
        .map(str::to_string)
        .unwrap_or_else(|| format!("Fan {}", position + 1));

    Some(FanReading { name, rpm })
}

/// `--charge-limit`: "Minimum 0%, Maximum 80%" (one or two lines).
pub fn charge_limit(stdout: &str) -> ChargeLimit {
    let mut out = ChargeLimit::default();

    for line in stdout.lines() {
        let l = line.to_ascii_lowercase();

        for part in l.split(',') {
            if part.contains("minimum") {
                out.charge_limit_min_pct = first_number(part).or(out.charge_limit_min_pct);
            }
            if part.contains("maximum") {
                out.charge_limit_max_pct = first_number(part).or(out.charge_limit_max_pct);
            }
        }
    }

    out
}

fn first_number(text: &str) -> Option<u8> {
    text.split(|c: char| !c.is_ascii_digit())
        .find(|t| !t.is_empty())
        .and_then(|t| t.parse().ok())
}

/// `--power -vv`: charger and battery status, one "Key: value unit" per line.
pub fn versions(text: &str) -> Versions {
    let mut out = Versions::default();
    let mut section = String::new();

    for raw in text.lines() {
        let line = raw.replace('\t', "    ");
        if line.trim().is_empty() {
            continue;
        }

        if let Some(v) = line.trim().strip_prefix("Tool Version:") {
            out.tool_version = Some(v.trim().to_string());
            continue;
        }

        if !line.starts_with(' ') {
            section = line.trim().to_ascii_lowercase();
            continue;
        }

        let Some((key, value)) = line.split_once(':') else {
            continue;
        };
        let key = key.trim().to_ascii_lowercase();
        let value = Some(value.trim().to_string());

        if section.starts_with("mainboard hardware") {
            match key.as_str() {
                "type" => out.mainboard_type = value,
                "revision" => out.mainboard_revision = value,
                _ => {}
            }
        } else if section.starts_with("uefi bios") {
            match key.as_str() {
                "version" => out.uefi_version = value,
                "release date" => out.uefi_release_date = value,
                _ => {}
            }
        } else if section.starts_with("ec firmware") {
            match key.as_str() {
                "build version" => out.ec_build_version = value,
                "current image" => out.ec_current_image = value,
                _ => {}
            }
        }
    }

    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rpms(t: &Thermal) -> Vec<u32> {
        t.fans.iter().map(|f| f.rpm).collect()
    }

    #[test]
    fn thermal_framework13() {
        let t = thermal(
            "  F75303_Local:   45 C\n  F75303_CPU:     55 C\n  APU:            62 C\n  Fan Speed:    3171 RPM\n",
        );
        assert_eq!(t.temps.get("cpu@4c"), Some(&62), "APU under its hwmon name");
        assert_eq!(t.temps.get("cpu_f75303@4d"), Some(&55));
        assert_eq!(rpms(&t), vec![3171]);
    }

    #[test]
    fn thermal_framework16_two_fans_and_unpowered_dgpu() {
        let s = "  F75303_Local: 40 C\n  APU:          39 C\n  dGPU VR:      0 C\n  dGPU temp:    NotPowered\n  Fan Speed:  2165 RPM\n  Fan Speed:  2035 RPM\n";
        let t = thermal(s);
        assert_eq!(t.temps.get("dGPU VR"), Some(&0));
        assert_eq!(t.temps.get("dGPU temp"), None);
        assert_eq!(rpms(&t), vec![2165, 2035]);
        assert_eq!(t.fans[1].name, "Fan Speed");
    }

    #[test]
    fn thermal_stalled_fan_reads_zero_and_keeps_its_slot() {
        let t = thermal("  Left Fan:  65534 RPM (Stalled)\n  Right Fan:  1300 RPM\n");
        assert_eq!(rpms(&t), vec![0, 1300]);
        assert_eq!(t.fans[0].name, "Left Fan");
    }

    #[test]
    fn thermal_ignores_rpm_without_number() {
        let t = thermal("  Note: fans report in RPM\n  Left Fan:  1200 RPM\n");
        assert_eq!(rpms(&t), vec![1200]);
    }

    #[test]
    fn charge_limit_one_line() {
        let c = charge_limit("Minimum 0%, Maximum 80%\n");
        assert_eq!(c.charge_limit_min_pct, Some(0));
        assert_eq!(c.charge_limit_max_pct, Some(80));
    }

    #[test]
    fn charge_limit_two_lines() {
        let c = charge_limit("Minimum: 90%\nMaximum: 90%\n");
        assert_eq!(c.charge_limit_min_pct, Some(90));
        assert_eq!(c.charge_limit_max_pct, Some(90));
    }

    #[test]
    fn versions_sections() {
        let s = "Tool Version:     0.6.4\nMainboard Hardware\n  Type:           Laptop 13 (AMD Ryzen 7040Series)\n  Revision:       MassProduction\nUEFI BIOS\n  Version:        03.18\n  Release Date:   01/08/2026\nEC Firmware\n  Build version:  azalea_v3.4\n  Current image:  RO\n";
        let v = versions(s);
        assert_eq!(v.tool_version.as_deref(), Some("0.6.4"));
        assert_eq!(
            v.mainboard_type.as_deref(),
            Some("Laptop 13 (AMD Ryzen 7040Series)")
        );
        assert_eq!(v.uefi_release_date.as_deref(), Some("01/08/2026"));
        assert_eq!(v.ec_current_image.as_deref(), Some("RO"));
    }
}

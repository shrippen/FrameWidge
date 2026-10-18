//! Parsers for the text output of `framework_tool`.
//!
//! Ported from framework-control by Kemal Ozturk (MIT, see LICENSE):
//! `service/src/cli/framework_tool_parser.rs`. Test samples are real
//! output of Framework 13 and 16 laptops.

use serde::Serialize;
use std::collections::BTreeMap;

/// EC fan-speed sentinels: 0xFFFE = stalled (printed as 65534), 0xFFFF = not present.
const EC_FAN_SENTINEL_MIN: u32 = 0xFFFE;

#[derive(Debug, Clone, Default, Serialize)]
pub struct Thermal {
    pub temps: BTreeMap<String, i32>,
    pub fans: Vec<FanReading>,
}

#[derive(Debug, Clone, Serialize)]
pub struct FanReading {
    pub name: String,
    pub rpm: u32,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct Battery {
    pub ac_present: Option<bool>,
    pub battery_present: Option<bool>,
    pub last_full_charge_capacity_mah: Option<u32>,
    pub remaining_capacity_mah: Option<u32>,
    pub percentage: Option<u32>,
    pub soc_pct: Option<u32>,
    pub present_voltage_mv: Option<u32>,
    pub present_rate_ma: Option<u32>,
    pub charger_voltage_mv: Option<u32>,
    pub charger_current_ma: Option<u32>,
    pub charge_input_current_ma: Option<u32>,
    pub design_capacity_mah: Option<u32>,
    pub design_voltage_mv: Option<u32>,
    pub cycle_count: Option<u32>,
    pub charging: Option<bool>,
    pub discharging: Option<bool>,
}

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
pub fn thermal(stdout: &str) -> Thermal {
    let mut out = Thermal::default();

    for line in stdout.lines() {
        let l = line.trim();

        if let Some((key, value)) = temperature(l) {
            out.temps.insert(key, value);
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
pub fn battery(stdout: &str) -> Battery {
    let mut out = Battery::default();

    for line in stdout.lines() {
        let l = line.trim();

        if let Some(rest) = l.strip_prefix("AC is:") {
            out.ac_present = Some(connected(rest));
            continue;
        }
        if let Some(rest) = l.strip_prefix("Battery is:") {
            out.battery_present = Some(connected(rest));
            continue;
        }
        if l.eq_ignore_ascii_case("Battery charging") {
            out.charging = Some(true);
            continue;
        }
        if l.eq_ignore_ascii_case("Battery discharging") {
            out.discharging = Some(true);
            continue;
        }

        let Some((key, rest)) = l.split_once(':') else {
            continue;
        };
        let rest = rest.trim();

        match key.trim() {
            "Battery LFCC" => out.last_full_charge_capacity_mah = integer(rest, ""),
            "Battery Capacity" => out.remaining_capacity_mah = integer(rest, ""),
            "Charge level" => out.percentage = integer(rest, "%"),
            "Battery SoC" => out.soc_pct = integer(rest, "%"),
            "Present Voltage" => out.present_voltage_mv = volts_as_mv(rest),
            "Present Rate" => out.present_rate_ma = integer(rest, ""),
            "Charger Voltage" => out.charger_voltage_mv = integer(rest, "mV"),
            "Charger Current" => out.charger_current_ma = integer(rest, "mA"),
            "Chg Input Current" => out.charge_input_current_ma = integer(rest, "mA"),
            "Design Capacity" => out.design_capacity_mah = integer(rest, ""),
            "Design Voltage" => out.design_voltage_mv = volts_as_mv(rest),
            "Cycle Count" => out.cycle_count = integer(rest, ""),
            _ => {}
        }
    }

    out
}

fn connected(text: &str) -> bool {
    let t = text.to_ascii_lowercase();
    t.contains("connected") && !t.contains("not connected")
}

/// First token that is a number once `unit` is cut off: "3221 mA" -> 3221, "52%" -> 52.
fn integer(text: &str, unit: &str) -> Option<u32> {
    text.split_whitespace()
        .map(|t| t.strip_suffix(unit).unwrap_or(t))
        .find(|t| !t.is_empty() && t.chars().all(|c| c.is_ascii_digit()))
        .and_then(|t| t.parse().ok())
}

/// "16.591 V" -> 16591.
fn volts_as_mv(text: &str) -> Option<u32> {
    let token = text
        .split_whitespace()
        .find(|t| t.chars().all(|c| c.is_ascii_digit() || c == '.'))?;
    let volts: f32 = token.parse().ok()?;
    Some((volts * 1000.0).round() as u32)
}

/// `--versions`: sections ("UEFI BIOS") with indented "Key: value" lines.
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
        assert_eq!(t.temps.get("APU"), Some(&62));
        assert_eq!(t.temps.get("F75303_CPU"), Some(&55));
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

    #[test]
    fn battery_verbose_sample() {
        let s = r#"
Charger Status
  AC is:            connected
  Charger Voltage:  17800mV
  Charger Current:  3568mA
  Chg Input Current:4400mA
  Battery SoC:      52%
Battery Status
  AC is:            connected
  Battery is:       connected
  Battery LFCC:     5182 mAh (Last Full Charge Capacity)
  Battery Capacity: 2685 mAh
  Charge level:     51%
  Present Voltage:  16.591 V
  Present Rate:     3221 mA
  Design Capacity:  5491 mAh
  Design Voltage:   15.480 V
  Cycle Count:      58
  Battery charging
"#;
        let p = battery(s);
        assert_eq!(p.ac_present, Some(true));
        assert_eq!(p.battery_present, Some(true));
        assert_eq!(p.last_full_charge_capacity_mah, Some(5182));
        assert_eq!(p.remaining_capacity_mah, Some(2685));
        assert_eq!(p.percentage, Some(51));
        assert_eq!(p.soc_pct, Some(52));
        assert_eq!(p.present_voltage_mv, Some(16591));
        assert_eq!(p.present_rate_ma, Some(3221));
        assert_eq!(p.charger_voltage_mv, Some(17800));
        assert_eq!(p.charger_current_ma, Some(3568));
        assert_eq!(p.charge_input_current_ma, Some(4400));
        assert_eq!(p.design_capacity_mah, Some(5491));
        assert_eq!(p.design_voltage_mv, Some(15480));
        assert_eq!(p.cycle_count, Some(58));
        assert_eq!(p.charging, Some(true));
    }

    #[test]
    fn battery_not_connected_ac() {
        let p = battery("  AC is:            not connected\n  Battery discharging\n");
        assert_eq!(p.ac_present, Some(false));
        assert_eq!(p.discharging, Some(true));
    }
}

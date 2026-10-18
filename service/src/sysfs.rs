//! Driver for the kernel's view of the laptop: the EC's temperatures and
//! fan speeds (hwmon `cros_ec`) and battery and charger (power_supply).
//! Plain file reads, no root and no EC traffic.

use crate::sensors::{self, Thermal};
use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};

pub const SYSFS: &str = "/sys";

/// hwmon name of the EC driver (cros_ec_hwmon, Linux 6.11+).
const EC_HWMON: &str = "cros_ec";
const MILLI: i64 = 1000;

#[derive(Debug, Clone, Default, Serialize, PartialEq)]
pub struct Battery {
    pub ac_present: Option<bool>,
    pub battery_present: Option<bool>,
    pub percentage: Option<u32>,
    pub charging: Option<bool>,
    pub discharging: Option<bool>,
    pub present_rate_ma: Option<u32>,
    pub present_voltage_mv: Option<u32>,
    pub remaining_capacity_mah: Option<u32>,
    pub last_full_charge_capacity_mah: Option<u32>,
    pub design_capacity_mah: Option<u32>,
    pub design_voltage_mv: Option<u32>,
    pub cycle_count: Option<u32>,
}

pub struct Sysfs {
    /// `class/hwmon/hwmonN` of the EC, if the kernel has the driver.
    ec_hwmon: Option<PathBuf>,
    power_supply: PathBuf,
}

impl Sysfs {
    pub fn new(root: &Path) -> Sysfs {
        let hwmon = root.join("class/hwmon");
        let ec_hwmon = entries(&hwmon)
            .into_iter()
            .find(|d| text(&d.join("name")).as_deref() == Some(EC_HWMON));

        Sysfs {
            ec_hwmon,
            power_supply: root.join("class/power_supply"),
        }
    }

    /// `None` without the EC hwmon driver; then `framework_tool` has to read.
    pub fn thermal(&self) -> Option<Thermal> {
        let dir = self.ec_hwmon.as_ref()?;
        let mut out = Thermal::default();

        // temp1_input, temp1_label, temp1_fault; millidegrees.
        for n in 1.. {
            let Some(milli) = number(&dir.join(format!("temp{n}_input"))) else {
                break;
            };
            if number(&dir.join(format!("temp{n}_fault"))) == Some(1) {
                continue;
            }
            let label =
                text(&dir.join(format!("temp{n}_label"))).unwrap_or_else(|| format!("temp{n}"));
            out.temps
                .insert(sensors::canonical(&label), (milli / MILLI) as i32);
        }

        // fan1_input in RPM; a faulty (stalled) fan reads 0 but keeps its slot.
        for n in 1.. {
            let Some(rpm) = number(&dir.join(format!("fan{n}_input"))) else {
                break;
            };
            let stalled = number(&dir.join(format!("fan{n}_fault"))) == Some(1);
            let rpm = if stalled {
                0
            } else {
                u32::try_from(rpm).unwrap_or(0)
            };
            out.fans.push(sensors::FanReading {
                name: format!("Fan {n}"),
                rpm,
            });
        }

        Some(out)
    }

    pub fn battery(&self) -> Battery {
        let supplies = entries(&self.power_supply);
        let of_type = |kind: &str| {
            supplies
                .iter()
                .find(|d| text(&d.join("type")).as_deref() == Some(kind))
        };

        let mut out = Battery {
            ac_present: of_type("Mains")
                .and_then(|d| number(&d.join("online")))
                .map(|v| v == 1),
            ..Battery::default()
        };

        let Some(bat) = of_type("Battery") else {
            return out;
        };
        let status = text(&bat.join("status")).unwrap_or_default();
        // µA, µV and µAh in sysfs; mA, mV and mAh in the API.
        let milli =
            |file: &str| number(&bat.join(file)).and_then(|v| u32::try_from(v.abs() / MILLI).ok());

        out.battery_present = number(&bat.join("present")).map(|v| v == 1);
        out.percentage = number(&bat.join("capacity")).and_then(|v| u32::try_from(v).ok());
        out.charging = Some(status == "Charging");
        out.discharging = Some(status == "Discharging");
        out.present_rate_ma = milli("current_now");
        out.present_voltage_mv = milli("voltage_now");
        out.remaining_capacity_mah = milli("charge_now");
        out.last_full_charge_capacity_mah = milli("charge_full");
        out.design_capacity_mah = milli("charge_full_design");
        out.design_voltage_mv = milli("voltage_min_design");
        out.cycle_count = number(&bat.join("cycle_count")).and_then(|v| u32::try_from(v).ok());
        out
    }
}

fn entries(dir: &Path) -> Vec<PathBuf> {
    let mut list: Vec<PathBuf> = fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .map(|e| e.path())
        .collect();
    list.sort();
    list
}

fn text(path: &Path) -> Option<String> {
    fs::read_to_string(path).ok().map(|s| s.trim().to_string())
}

fn number(path: &Path) -> Option<i64> {
    text(path)?.parse().ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A sysfs tree like a Framework 13 AMD's.
    fn fake(root: &Path) {
        let write = |rel: &str, value: &str| {
            let path = root.join(rel);
            fs::create_dir_all(path.parent().unwrap()).unwrap();
            fs::write(path, format!("{value}\n")).unwrap();
        };
        write("class/hwmon/hwmon2/name", "acpitz");
        write("class/hwmon/hwmon2/temp1_input", "99000");
        write("class/hwmon/hwmon11/name", "cros_ec");
        write("class/hwmon/hwmon11/temp1_label", "local_f75303@4d");
        write("class/hwmon/hwmon11/temp1_input", "36850");
        write("class/hwmon/hwmon11/temp2_label", "cpu@4c");
        write("class/hwmon/hwmon11/temp2_input", "71000");
        write("class/hwmon/hwmon11/temp3_label", "gpu@4d");
        write("class/hwmon/hwmon11/temp3_input", "0");
        write("class/hwmon/hwmon11/temp3_fault", "1");
        write("class/hwmon/hwmon11/fan1_input", "2200");
        write("class/power_supply/ACAD/type", "Mains");
        write("class/power_supply/ACAD/online", "1");
        write("class/power_supply/BAT1/type", "Battery");
        write("class/power_supply/BAT1/present", "1");
        write("class/power_supply/BAT1/status", "Charging");
        write("class/power_supply/BAT1/capacity", "77");
        write("class/power_supply/BAT1/current_now", "590000");
        write("class/power_supply/BAT1/voltage_now", "15581000");
        write("class/power_supply/BAT1/charge_now", "2270000");
        write("class/power_supply/BAT1/charge_full", "3448000");
        write("class/power_supply/BAT1/charge_full_design", "3915000");
        write("class/power_supply/BAT1/voltage_min_design", "15480000");
        write("class/power_supply/BAT1/cycle_count", "162");
    }

    fn root(name: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("framewidged-sysfs-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    #[test]
    fn reads_ec_hwmon_and_skips_faults() {
        let dir = root("thermal");
        fake(&dir);
        let t = Sysfs::new(&dir).thermal().unwrap();
        assert_eq!(t.temps.get("cpu@4c"), Some(&71));
        assert_eq!(t.temps.get("local_f75303@4d"), Some(&36));
        assert!(!t.temps.contains_key("gpu@4d"));
        assert_eq!(t.fans[0].rpm, 2200);
    }

    #[test]
    fn reads_battery_and_charger() {
        let dir = root("battery");
        fake(&dir);
        let b = Sysfs::new(&dir).battery();
        assert_eq!(b.ac_present, Some(true));
        assert_eq!(b.percentage, Some(77));
        assert_eq!(b.charging, Some(true));
        assert_eq!(b.present_rate_ma, Some(590));
        assert_eq!(b.present_voltage_mv, Some(15581));
        assert_eq!(b.last_full_charge_capacity_mah, Some(3448));
        assert_eq!(b.design_capacity_mah, Some(3915));
        assert_eq!(b.cycle_count, Some(162));
    }

    #[test]
    fn without_ec_driver_there_is_no_thermal() {
        let dir = root("none");
        fs::create_dir_all(dir.join("class/hwmon/hwmon0")).unwrap();
        fs::write(dir.join("class/hwmon/hwmon0/name"), "acpitz\n").unwrap();
        assert!(Sysfs::new(&dir).thermal().is_none());
        assert_eq!(Sysfs::new(&dir).battery(), Battery::default());
    }
}

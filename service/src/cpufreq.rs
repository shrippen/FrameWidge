//! Driver for the kernel's cpufreq sysfs files: governor, frequency limits
//! and (amd-pstate, intel_pstate) the energy performance preference (EPP).
//!
//! Follows framework-control's `service/src/cli/linux_power.rs` (MIT).

use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};

pub const SYSFS_CPU: &str = "/sys/devices/system/cpu";

const KHZ_PER_MHZ: u64 = 1000;

#[derive(Debug, Clone, Default, Serialize)]
pub struct Capabilities {
    pub supports_epp: bool,
    pub supports_governor: bool,
    pub supports_frequency_limits: bool,
    pub supports_tdp: bool,
    pub supports_thermal: bool,
    pub available_epp_preferences: Option<Vec<String>>,
    pub available_governors: Option<Vec<String>>,
    pub frequency_min_mhz: Option<u32>,
    pub frequency_max_mhz: Option<u32>,
    pub tdp_min_watts: Option<u32>,
    pub tdp_max_watts: Option<u32>,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct State {
    pub epp_preference: Option<String>,
    pub governor: Option<String>,
    /// Lowest and highest current frequency across cores (live, not the limits).
    pub min_freq_mhz: Option<u32>,
    pub max_freq_mhz: Option<u32>,
    pub tdp_limit_watts: Option<u32>,
    pub thermal_limit_c: Option<u32>,
}

pub struct Cpufreq {
    /// `.../cpuN/cpufreq` of every CPU with a governor, sorted by N.
    cpus: Vec<PathBuf>,
}

impl Cpufreq {
    pub fn new(root: &Path) -> Cpufreq {
        let mut cpus: Vec<(u32, PathBuf)> = fs::read_dir(root)
            .into_iter()
            .flatten()
            .flatten()
            .filter_map(|e| {
                let name = e.file_name().into_string().ok()?;
                let index = name.strip_prefix("cpu")?.parse::<u32>().ok()?;
                let dir = e.path().join("cpufreq");
                dir.join("scaling_governor")
                    .is_file()
                    .then_some((index, dir))
            })
            .collect();
        cpus.sort_by_key(|(i, _)| *i);

        Cpufreq {
            cpus: cpus.into_iter().map(|(_, d)| d).collect(),
        }
    }

    pub fn capabilities(&self) -> Capabilities {
        let Some(first) = self.cpus.first() else {
            return Capabilities::default();
        };

        let epp = list(&first.join("energy_performance_available_preferences"));
        Capabilities {
            supports_epp: epp.is_some(),
            supports_governor: true,
            supports_frequency_limits: true,
            available_epp_preferences: epp,
            available_governors: list(&first.join("scaling_available_governors")),
            frequency_min_mhz: mhz(&first.join("cpuinfo_min_freq")).filter(|&v| v > 0),
            frequency_max_mhz: mhz(&first.join("cpuinfo_max_freq")).filter(|&v| v > 0),
            ..Capabilities::default()
        }
    }

    pub fn state(&self) -> State {
        let Some(first) = self.cpus.first() else {
            return State::default();
        };

        let current: Vec<u32> = self
            .cpus
            .iter()
            .filter_map(|c| mhz(&c.join("scaling_cur_freq")))
            .collect();
        State {
            epp_preference: text(&first.join("energy_performance_preference")),
            governor: self.governor(),
            min_freq_mhz: current.iter().min().copied(),
            max_freq_mhz: current.iter().max().copied(),
            ..State::default()
        }
    }

    pub fn governor(&self) -> Option<String> {
        text(&self.cpus.first()?.join("scaling_governor"))
    }

    pub fn epp(&self) -> Option<String> {
        text(&self.cpus.first()?.join("energy_performance_preference"))
    }

    /// Configured limits (scaling_min/max_freq) of the first CPU.
    pub fn limits(&self) -> Option<(u32, u32)> {
        let first = self.cpus.first()?;
        Some((
            mhz(&first.join("scaling_min_freq"))?,
            mhz(&first.join("scaling_max_freq"))?,
        ))
    }

    pub fn hardware_range(&self) -> Option<(u32, u32)> {
        let first = self.cpus.first()?;
        Some((
            mhz(&first.join("cpuinfo_min_freq"))?,
            mhz(&first.join("cpuinfo_max_freq"))?,
        ))
    }

    pub fn set_governor(&self, value: &str) -> Result<(), String> {
        self.set_listed("scaling_governor", "scaling_available_governors", value)
    }

    pub fn set_epp(&self, value: &str) -> Result<(), String> {
        self.set_listed(
            "energy_performance_preference",
            "energy_performance_available_preferences",
            value,
        )
    }

    /// `None` resets that end to the hardware limit.
    pub fn set_limits(&self, min_mhz: Option<u32>, max_mhz: Option<u32>) -> Result<(), String> {
        let (hw_min, hw_max) = self.hardware_range().ok_or("no cpufreq limits")?;
        let max = max_mhz.unwrap_or(hw_max).clamp(hw_min, hw_max);
        let min = min_mhz.unwrap_or(hw_min).clamp(hw_min, max);

        for cpu in &self.cpus {
            // Max first, so the kernel never sees min > max.
            write(
                &cpu.join("scaling_max_freq"),
                &(max as u64 * KHZ_PER_MHZ).to_string(),
            )?;
            write(
                &cpu.join("scaling_min_freq"),
                &(min as u64 * KHZ_PER_MHZ).to_string(),
            )?;
        }
        Ok(())
    }

    /// Writes `value` to `file` of every CPU if `available` lists it.
    fn set_listed(&self, file: &str, available: &str, value: &str) -> Result<(), String> {
        let first = self.cpus.first().ok_or("no cpufreq")?;
        let allowed = list(&first.join(available)).unwrap_or_default();
        if !allowed.iter().any(|a| a == value) {
            return Err(format!("{value} not in {available} {allowed:?}"));
        }

        for cpu in &self.cpus {
            write(&cpu.join(file), value)?;
        }
        Ok(())
    }
}

fn text(path: &Path) -> Option<String> {
    fs::read_to_string(path).ok().map(|s| s.trim().to_string())
}

fn list(path: &Path) -> Option<Vec<String>> {
    text(path).map(|s| s.split_whitespace().map(str::to_string).collect())
}

fn mhz(path: &Path) -> Option<u32> {
    let khz: u64 = text(path)?.parse().ok()?;
    u32::try_from(khz / KHZ_PER_MHZ).ok()
}

fn write(path: &Path, value: &str) -> Result<(), String> {
    fs::write(path, value).map_err(|e| format!("{}: {e}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fake_sysfs(name: &str) -> PathBuf {
        let root =
            std::env::temp_dir().join(format!("framewidged-cpufreq-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        for cpu in ["cpu0", "cpu1", "cpu10"] {
            let d = root.join(cpu).join("cpufreq");
            fs::create_dir_all(&d).unwrap();
            fs::write(d.join("scaling_governor"), "powersave\n").unwrap();
            fs::write(
                d.join("scaling_available_governors"),
                "performance powersave\n",
            )
            .unwrap();
            fs::write(d.join("energy_performance_preference"), "balance_power\n").unwrap();
            fs::write(
                d.join("energy_performance_available_preferences"),
                "default performance power\n",
            )
            .unwrap();
            fs::write(d.join("cpuinfo_min_freq"), "400000\n").unwrap();
            fs::write(d.join("cpuinfo_max_freq"), "5100000\n").unwrap();
            fs::write(d.join("scaling_min_freq"), "400000\n").unwrap();
            fs::write(d.join("scaling_max_freq"), "5100000\n").unwrap();
            fs::write(
                d.join("scaling_cur_freq"),
                if cpu == "cpu1" {
                    "3000000\n"
                } else {
                    "1200000\n"
                },
            )
            .unwrap();
        }
        // Not a CPU directory.
        fs::create_dir_all(root.join("cpufreq")).unwrap();
        root
    }

    #[test]
    fn reads_capabilities_and_state() {
        let c = Cpufreq::new(&fake_sysfs("read"));
        let caps = c.capabilities();
        assert!(caps.supports_epp);
        assert_eq!(caps.frequency_max_mhz, Some(5100));
        assert_eq!(
            caps.available_governors.unwrap(),
            vec!["performance", "powersave"]
        );

        let s = c.state();
        assert_eq!(s.governor.as_deref(), Some("powersave"));
        assert_eq!((s.min_freq_mhz, s.max_freq_mhz), (Some(1200), Some(3000)));
    }

    #[test]
    fn writes_every_cpu_and_rejects_unknown_values() {
        let root = fake_sysfs("write");
        let c = Cpufreq::new(&root);

        c.set_governor("performance").unwrap();
        assert!(c.set_governor("ondemand").is_err());
        assert_eq!(
            text(&root.join("cpu10/cpufreq/scaling_governor")).unwrap(),
            "performance"
        );

        c.set_limits(Some(100), Some(2000)).unwrap();
        assert_eq!(c.limits(), Some((400, 2000)));
        assert_eq!(
            text(&root.join("cpu10/cpufreq/scaling_max_freq")).unwrap(),
            "2000000"
        );
    }

    #[test]
    fn no_cpufreq_means_no_capabilities() {
        let root =
            std::env::temp_dir().join(format!("framewidged-cpufreq-none-{}", std::process::id()));
        fs::create_dir_all(&root).unwrap();
        let caps = Cpufreq::new(&root).capabilities();
        assert!(!caps.supports_governor);
    }
}

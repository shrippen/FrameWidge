//! Persistent settings, in the schema the widget reads and writes via
//! `/api/config`. A POST is a partial patch: objects merge key by key,
//! everything else (arrays, numbers, null) replaces.
//!
//! On first start the settings of framework-control are taken over, so a
//! switch from that service keeps the fan curve and limits.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::fs;
use std::path::{Path, PathBuf};

const CONFIG_FILE: &str = "config.json";

/// framework-control's settings, imported once.
pub const LEGACY_CONFIG: &str = "/etc/framework-control/config.json";

pub const PCT_MAX: u32 = 100;
pub const CHARGE_LIMIT_MIN: u8 = 25;
pub const CHARGE_LIMIT_MAX: u8 = 100;
/// Lowest poll interval the widget offers; 0 would spin the fan loop.
const POLL_MS_MIN: u64 = 100;

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct Config {
    pub fan: FanConfig,
    pub power: PowerConfig,
    pub battery: BatteryConfig,
    pub telemetry: TelemetryConfig,
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum FanMode {
    /// The EC runs its own curve.
    #[default]
    Disabled,
    Manual,
    Curve,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct FanConfig {
    pub mode: FanMode,
    pub manual: Option<Manual>,
    pub curve: Option<Curve>,
    /// Per-fan settings (Framework 16 has two fans); a fan without one follows the global setting.
    pub overrides: Vec<Override>,
    /// Duty -> RPM table measured by the widget's calibration dialog; only stored here.
    pub calibration: Option<Value>,
}

impl Default for FanConfig {
    fn default() -> Self {
        FanConfig {
            mode: FanMode::Disabled,
            manual: Some(Manual { duty_pct: 50 }),
            curve: Some(Curve::default()),
            overrides: Vec::new(),
            calibration: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Manual {
    pub duty_pct: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct Curve {
    /// Hottest of these sensors drives the curve; none or unknown names: hottest of all.
    pub sensors: Vec<String>,
    /// [temperature °C, duty %]; [0,0] and [100,100] are implied.
    pub points: Vec<[u32; 2]>,
    /// A falling temperature lowers the duty only after dropping this far.
    pub hysteresis_c: u32,
    pub rate_limit_pct_per_step: u32,
    /// Spin-down step; unset: same as spin-up.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rate_limit_down_pct_per_step: Option<u32>,
    pub poll_ms: u64,
}

impl Default for Curve {
    fn default() -> Self {
        Curve {
            sensors: Vec::new(),
            points: vec![[40, 0], [60, 40], [75, 80], [85, 100]],
            hysteresis_c: 2,
            rate_limit_pct_per_step: 100,
            rate_limit_down_pct_per_step: None,
            poll_ms: 2000,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Override {
    pub index: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub manual: Option<Manual>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub curve: Option<Curve>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct PowerConfig {
    pub ac: Option<PowerProfile>,
    pub battery: Option<PowerProfile>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct PowerProfile {
    pub epp_preference: Option<Setting<String>>,
    pub governor: Option<Setting<String>>,
    pub min_freq_mhz: Option<Setting<u32>>,
    pub max_freq_mhz: Option<Setting<u32>>,
    /// Kept for the widget; Linux has no TDP or thermal-limit control here.
    pub tdp_watts: Option<Setting<u32>>,
    pub thermal_limit_c: Option<Setting<u32>>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Setting<T> {
    pub enabled: bool,
    pub value: T,
}

impl<T> Setting<T> {
    pub fn active(&self) -> Option<&T> {
        self.enabled.then_some(&self.value)
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct BatteryConfig {
    pub charge_limit_max_pct: Option<Setting<u8>>,
    pub charge_rate_c: Option<Setting<f32>>,
    pub charge_rate_soc_threshold_pct: Option<u8>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct TelemetryConfig {
    pub poll_ms: u64,
    pub retain_seconds: u64,
}

impl Default for TelemetryConfig {
    fn default() -> Self {
        TelemetryConfig {
            poll_ms: 2000,
            retain_seconds: 1800,
        }
    }
}

impl Config {
    /// Applies a partial patch; the result must still be a valid config.
    pub fn patched(&self, patch: &Value) -> Result<Config, String> {
        if !patch.is_object() {
            return Err("patch must be a JSON object".into());
        }

        let mut merged = serde_json::to_value(self).map_err(|e| e.to_string())?;
        merge(&mut merged, patch);
        let cfg: Config = serde_json::from_value(merged).map_err(|e| e.to_string())?;
        cfg.validate()?;
        Ok(cfg)
    }

    fn validate(&self) -> Result<(), String> {
        let fan = &self.fan;
        let curves = fan
            .curve
            .iter()
            .chain(fan.overrides.iter().filter_map(|o| o.curve.as_ref()));
        for curve in curves {
            if curve
                .points
                .iter()
                .any(|[t, d]| *t > PCT_MAX || *d > PCT_MAX)
            {
                return Err("curve points must be within 0..100".into());
            }
            if curve.rate_limit_pct_per_step == 0 || curve.rate_limit_down_pct_per_step == Some(0) {
                return Err("rate limit must be at least 1".into());
            }
            if curve.poll_ms < POLL_MS_MIN {
                return Err(format!("curve poll_ms must be at least {POLL_MS_MIN}"));
            }
        }

        let manuals = fan
            .manual
            .iter()
            .chain(fan.overrides.iter().filter_map(|o| o.manual.as_ref()));
        if manuals.into_iter().any(|m| m.duty_pct > PCT_MAX) {
            return Err("duty must be within 0..100".into());
        }

        if let Some(limit) = self
            .battery
            .charge_limit_max_pct
            .as_ref()
            .and_then(Setting::active)
        {
            if !(CHARGE_LIMIT_MIN..=CHARGE_LIMIT_MAX).contains(limit) {
                return Err(format!(
                    "charge limit must be within {CHARGE_LIMIT_MIN}..{CHARGE_LIMIT_MAX}"
                ));
            }
        }

        Ok(())
    }
}

fn merge(dst: &mut Value, patch: &Value) {
    let (Value::Object(dst), Value::Object(patch)) = (&mut *dst, patch) else {
        *dst = patch.clone();
        return;
    };
    for (key, value) in patch {
        match dst.get_mut(key) {
            Some(slot) if slot.is_object() && value.is_object() => merge(slot, value),
            _ => {
                dst.insert(key.clone(), value.clone());
            }
        }
    }
}

/// The settings file in the state directory.
pub struct Store {
    path: PathBuf,
}

impl Store {
    pub fn new(state_dir: &Path) -> Store {
        Store {
            path: state_dir.join(CONFIG_FILE),
        }
    }

    /// Own file, else framework-control's (imported), else defaults.
    pub fn load(&self, legacy: &Path) -> Config {
        if let Ok(text) = fs::read_to_string(&self.path) {
            return match serde_json::from_str(&text) {
                Ok(cfg) => cfg,
                Err(e) => {
                    eprintln!("<4>{}: {e}; using defaults", self.path.display());
                    Config::default()
                }
            };
        }

        let Ok(text) = fs::read_to_string(legacy) else {
            return Config::default();
        };
        let cfg = serde_json::from_str::<Value>(&text)
            .map(|v| import(&v))
            .unwrap_or_default();
        eprintln!("<5>imported settings from {}", legacy.display());
        if let Err(e) = self.save(&cfg) {
            eprintln!("<4>{e}");
        }
        cfg
    }

    /// Atomic: a crash mid-write leaves the old file.
    pub fn save(&self, cfg: &Config) -> Result<(), String> {
        let text = serde_json::to_string_pretty(cfg).map_err(|e| e.to_string())?;
        let tmp = self.path.with_extension("json.tmp");
        if let Some(dir) = self.path.parent() {
            fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
        }
        fs::write(&tmp, text).map_err(|e| format!("{}: {e}", tmp.display()))?;
        fs::rename(&tmp, &self.path).map_err(|e| format!("{}: {e}", self.path.display()))
    }
}

/// framework-control config, before (flat `fan`) or since 0.5.5 (`fan.profiles`).
fn import(legacy: &Value) -> Config {
    let mut v = legacy.clone();

    if let Some(fan) = v.get_mut("fan").and_then(Value::as_object_mut) {
        let active = fan
            .get("active_profile")
            .and_then(Value::as_str)
            .unwrap_or("default")
            .to_string();
        let profile = fan
            .get("profiles")
            .and_then(Value::as_array)
            .and_then(|ps| ps.iter().find(|p| p["id"] == active.as_str()).cloned());
        if let Some(Value::Object(profile)) = profile {
            for key in ["mode", "manual", "curve", "overrides"] {
                if let Some(value) = profile.get(key) {
                    fan.insert(key.into(), value.clone());
                }
            }
        }

        // 0.5.5 calibrates per fan; the widget keeps one table.
        let first_fan = fan
            .get("calibration")
            .and_then(|c| c["fans"][0]["points"].as_array())
            .cloned();
        if let Some(points) = first_fan {
            let updated_at = fan["calibration"]["updated_at"].clone();
            fan.insert(
                "calibration".into(),
                serde_json::json!({ "points": points, "updated_at": updated_at }),
            );
        }
    }

    // Fields this service does not know are dropped, invalid sections reset.
    let defaults = serde_json::to_value(Config::default()).unwrap_or_default();
    let mut cfg = Config::default();
    for section in ["fan", "power", "battery", "telemetry"] {
        let mut merged = defaults.clone();
        merge(
            &mut merged,
            &serde_json::json!({ section: v[section].clone() }),
        );
        match serde_json::from_value::<Config>(merged) {
            Ok(c) if c.validate().is_ok() => match section {
                "fan" => cfg.fan = c.fan,
                "power" => cfg.power = c.power,
                "battery" => cfg.battery = c.battery,
                _ => cfg.telemetry = c.telemetry,
            },
            _ => eprintln!("<4>framework-control {section} settings not imported"),
        }
    }
    cfg
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn patch_merges_objects_and_replaces_arrays() {
        let cfg = Config::default()
            .patched(&json!({ "fan": { "mode": "curve", "curve": { "points": [[50, 50]] } } }))
            .unwrap();
        assert_eq!(cfg.fan.mode, FanMode::Curve);
        let curve = cfg.fan.curve.unwrap();
        assert_eq!(curve.points, vec![[50, 50]]);
        assert_eq!(curve.hysteresis_c, 2, "untouched keys stay");
    }

    #[test]
    fn patch_into_null_profile() {
        let cfg = Config::default()
            .patched(&json!({ "power": { "ac": { "max_freq_mhz": { "enabled": true, "value": 3000 } } } }))
            .unwrap();
        let ac = cfg.power.ac.unwrap();
        assert_eq!(ac.max_freq_mhz.unwrap().value, 3000);
        assert!(ac.governor.is_none());
    }

    #[test]
    fn patch_rejects_invalid_values() {
        let base = Config::default();
        assert!(base
            .patched(&json!({ "fan": { "mode": "turbo" } }))
            .is_err());
        assert!(base
            .patched(&json!({ "fan": { "manual": { "duty_pct": 120 } } }))
            .is_err());
        assert!(base
            .patched(
                &json!({ "battery": { "charge_limit_max_pct": { "enabled": true, "value": 10 } } })
            )
            .is_err());
        assert!(base.patched(&json!([1])).is_err());
    }

    #[test]
    fn patch_ignores_unknown_keys() {
        let cfg = Config::default()
            .patched(&json!({ "ui": { "theme": "x" } }))
            .unwrap();
        assert_eq!(cfg, Config::default());
    }

    #[test]
    fn import_framework_control_0_5_5_profiles() {
        let legacy = json!({
            "fan": {
                "active_profile": "quiet",
                "calibration": { "fans": [{ "index": 0, "points": [[0, 0], [100, 8260]] }], "updated_at": 7 },
                "profiles": [
                    { "id": "default", "mode": "disabled" },
                    { "id": "quiet", "mode": "curve", "manual": { "duty_pct": 100 },
                      "curve": { "points": [[0, 16], [83, 100]], "hysteresis_c": 2, "poll_ms": 2000,
                                 "rate_limit_pct_per_step": 100, "sensors": ["APU"] }, "overrides": [] }
                ]
            },
            "battery": { "charge_limit_max_pct": { "enabled": true, "value": 90 }, "charge_rate_c": null },
            "power": { "ac": null, "battery": { "governor": { "enabled": false, "value": "" } } },
            "telemetry": { "poll_ms": 1000 },
            "ui": { "theme": null },
            "version": 1
        });
        let cfg = import(&legacy);
        assert_eq!(cfg.fan.mode, FanMode::Curve);
        assert_eq!(cfg.fan.curve.as_ref().unwrap().sensors, vec!["APU"]);
        assert_eq!(
            cfg.fan.calibration.as_ref().unwrap()["points"],
            json!([[0, 0], [100, 8260]])
        );
        assert_eq!(cfg.battery.charge_limit_max_pct.unwrap().value, 90);
        assert_eq!(cfg.telemetry.poll_ms, 1000);
        assert_eq!(cfg.telemetry.retain_seconds, 1800);
        assert!(cfg.power.ac.is_none());
    }

    #[test]
    fn import_flat_fan_settings_and_skip_broken_sections() {
        let legacy = json!({
            "fan": { "mode": "manual", "manual": { "duty_pct": 42 } },
            "battery": { "charge_limit_max_pct": { "enabled": true, "value": "lots" } }
        });
        let cfg = import(&legacy);
        assert_eq!(cfg.fan.mode, FanMode::Manual);
        assert_eq!(cfg.fan.manual.unwrap().duty_pct, 42);
        assert_eq!(cfg.battery, BatteryConfig::default());
    }

    #[test]
    fn store_round_trip_and_first_start_import() {
        let dir = std::env::temp_dir().join(format!("framewidged-store-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        let legacy = dir.join("legacy.json");
        fs::create_dir_all(&dir).unwrap();
        fs::write(
            &legacy,
            r#"{"fan":{"mode":"manual","manual":{"duty_pct":30}}}"#,
        )
        .unwrap();

        let store = Store::new(&dir.join("state"));
        assert_eq!(store.load(&legacy).fan.mode, FanMode::Manual);

        // The import was saved; the legacy file is not read again.
        fs::write(&legacy, r#"{"fan":{"mode":"curve"}}"#).unwrap();
        assert_eq!(store.load(&legacy).fan.mode, FanMode::Manual);
    }
}

//! Temperature and fan readings, whichever driver produced them, under one
//! set of sensor names.
//!
//! The names are the kernel's hwmon labels (`cpu@4c`), which newer
//! `framework_tool` versions print as well. Older `framework_tool` versions
//! (and so fan curves saved with them) use other names; `canonical` maps
//! the known ones, so a curve keeps its sensors whichever source reads.

use serde::Serialize;
use std::collections::BTreeMap;

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

/// Old `framework_tool` name -> hwmon label (Framework 13/16 AMD, verified on a 13 AMD).
const LEGACY_NAMES: [(&str, &str); 4] = [
    ("F75303_Local", "local_f75303@4d"),
    ("F75303_CPU", "cpu_f75303@4d"),
    ("F75303_DDR", "ddr_f75303@4d"),
    ("APU", "cpu@4c"),
];

pub fn canonical(name: &str) -> String {
    LEGACY_NAMES
        .iter()
        .find(|(old, _)| old.eq_ignore_ascii_case(name))
        .map_or_else(|| name.to_string(), |(_, new)| new.to_string())
}

/// Hottest of `wanted` (case-insensitive). If none of them exists, e.g.
/// after an EC update renamed the sensors, the hottest of all, so a fan
/// never stays on a stale reading.
pub fn hottest(temps: &BTreeMap<String, i32>, wanted: &[String]) -> Option<i32> {
    let picked = wanted
        .iter()
        .filter_map(|name| {
            let name = canonical(name);
            temps.get(&name).or_else(|| {
                temps
                    .iter()
                    .find(|(k, _)| k.eq_ignore_ascii_case(&name))
                    .map(|(_, v)| v)
            })
        })
        .max()
        .copied();

    picked.or_else(|| temps.values().max().copied())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_old_tool_names() {
        assert_eq!(canonical("APU"), "cpu@4c");
        assert_eq!(canonical("f75303_cpu"), "cpu_f75303@4d");
        assert_eq!(canonical("cpu@4c"), "cpu@4c");
        assert_eq!(canonical("PECI"), "PECI");
    }

    #[test]
    fn hottest_uses_selected_then_falls_back() {
        let temps: BTreeMap<String, i32> = [
            ("cpu_f75303@4d".to_string(), 58),
            ("cpu@4c".to_string(), 62),
        ]
        .into();
        assert_eq!(
            hottest(&temps, &["F75303_CPU".to_string()]),
            Some(58),
            "old name still selects"
        );
        assert_eq!(
            hottest(&temps, &["CPU_F75303@4D".to_string(), "gpu".to_string()]),
            Some(58)
        );
        assert_eq!(hottest(&temps, &["gone".to_string()]), Some(62));
        assert_eq!(hottest(&BTreeMap::new(), &[]), None);
    }
}

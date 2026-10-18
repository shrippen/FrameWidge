//! Temperature and fan readings, whichever driver produced them, under one
//! set of sensor names.
//!
//! The names are those of `framework_tool` 0.6.6: temperatures as the EC
//! names them (`cpu@4c`; the kernel's hwmon labels come from the same EC
//! command), fans by model (`APU Fan`). Older `framework_tool` versions (and
//! so fan curves saved with them) use other temperature names; `canonical`
//! maps the known ones, so a curve keeps its sensors whichever source reads.

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

/// Framework product family, from the SMBIOS product name.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Family {
    Laptop12,
    Laptop13,
    Laptop16,
    Desktop,
}

impl Family {
    /// As framework_tool 0.6.6 sorts them; a plain "Laptop" is the first Laptop 13
    /// ("Laptop (12th Gen Intel Core)" too).
    pub fn from_product(name: &str) -> Option<Family> {
        let family = if name.starts_with("Laptop 12") {
            Family::Laptop12
        } else if name.starts_with("Laptop 16") {
            Family::Laptop16
        } else if name.starts_with("Desktop") {
            Family::Desktop
        } else if name.starts_with("Laptop") {
            Family::Laptop13
        } else {
            return None;
        };
        Some(family)
    }
}

/// Fan name as framework_tool 0.6.6 prints it; `index` counts from 0.
pub fn fan_name(family: Option<Family>, index: usize) -> String {
    let name = match (index, family) {
        (0, Some(Family::Laptop12 | Family::Laptop13 | Family::Desktop)) => "APU Fan",
        (0, Some(Family::Laptop16)) => "Left Fan",
        (1, Some(Family::Laptop16)) => "Right Fan",
        (1, Some(Family::Desktop)) => "Front Fan",
        (2, Some(Family::Desktop)) => "Third Fan",
        _ => return format!("Fan {index}"),
    };
    name.to_string()
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
    fn names_fans_like_framework_tool() {
        let fw13 = Family::from_product("Laptop 13 (AMD Ryzen 7040Series)");
        let fw16 = Family::from_product("Laptop 16 (AMD Ryzen AI 300 Series)");
        assert_eq!(fw13, Some(Family::Laptop13));
        assert_eq!(
            Family::from_product("Laptop (12th Gen Intel Core)"),
            Some(Family::Laptop13)
        );
        assert_eq!(
            Family::from_product("Laptop 12 (13th Gen Intel Core)"),
            Some(Family::Laptop12)
        );
        assert_eq!(Family::from_product("ThinkPad X1"), None);

        assert_eq!(fan_name(fw13, 0), "APU Fan");
        assert_eq!(fan_name(fw16, 1), "Right Fan");
        assert_eq!(fan_name(Some(Family::Desktop), 2), "Third Fan");
        assert_eq!(fan_name(fw13, 1), "Fan 1");
        assert_eq!(fan_name(None, 0), "Fan 0");
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

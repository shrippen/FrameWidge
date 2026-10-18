//! Charge control: keeps the EC's charge limit and charge rate at the
//! configured values. The EC forgets them on some events (firmware
//! update, battery disconnect), so they are written again every few minutes.
//!
//! A limit switched off is left as it is, like framework-control does.

use crate::config::{BatteryConfig, CHARGE_LIMIT_MAX, CHARGE_LIMIT_MIN};
use crate::tool::Tool;
use std::time::{Duration, Instant};

const REAPPLY: Duration = Duration::from_secs(10 * 60);

/// Charge rate in C, in the 0.05 steps of the widget's slider.
const RATE_STEP: f32 = 0.05;
const RATE_MAX: f32 = 1.0;

#[derive(Default)]
pub struct Charge {
    limit: Applied<u8>,
    /// Rate in RATE_STEPs (integers compare exactly) and the SoC it starts at.
    rate: Applied<(u32, Option<u8>)>,
}

impl Charge {
    pub fn step(&mut self, tool: &Tool, battery: &BatteryConfig) {
        let wanted_limit = battery
            .charge_limit_max_pct
            .as_ref()
            .and_then(|s| s.active())
            .map(|v| (*v).clamp(CHARGE_LIMIT_MIN, CHARGE_LIMIT_MAX));
        self.limit.keep(wanted_limit, |v| tool.set_charge_limit(*v));

        let wanted_rate = battery
            .charge_rate_c
            .as_ref()
            .and_then(|s| s.active())
            .map(|c| {
                let steps = (c.clamp(RATE_STEP, RATE_MAX) / RATE_STEP).round() as u32;
                (steps, battery.charge_rate_soc_threshold_pct)
            });
        self.rate.keep(wanted_rate, |(steps, soc)| {
            tool.set_charge_rate(*steps as f32 * RATE_STEP, *soc)
        });
    }
}

/// Last value written and when.
struct Applied<T> {
    value: Option<T>,
    at: Option<Instant>,
}

impl<T> Default for Applied<T> {
    fn default() -> Self {
        Applied {
            value: None,
            at: None,
        }
    }
}

impl<T: PartialEq + Clone + std::fmt::Debug> Applied<T> {
    /// Writes `wanted` when it changed or REAPPLY passed; `None` forgets the last value.
    fn keep(&mut self, wanted: Option<T>, write: impl FnOnce(&T) -> Result<(), String>) {
        let Some(wanted) = wanted else {
            *self = Applied::default();
            return;
        };

        let due = self.at.is_none_or(|t| t.elapsed() >= REAPPLY);
        if self.value.as_ref() == Some(&wanted) && !due {
            return;
        }

        // A failed write is retried after REAPPLY (or on a new value), not every tick.
        if let Err(e) = write(&wanted) {
            eprintln!("<4>battery: {wanted:?}: {e}");
        }
        self.value = Some(wanted);
        self.at = Some(Instant::now());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;

    #[test]
    fn writes_on_change_only() {
        let writes = Cell::new(0);
        let mut a = Applied::<u8>::default();
        let write = |_: &u8| {
            writes.set(writes.get() + 1);
            Ok(())
        };

        a.keep(Some(80), write);
        a.keep(Some(80), write);
        assert_eq!(writes.get(), 1);

        a.keep(Some(90), write);
        assert_eq!(writes.get(), 2);

        a.keep(None, write);
        a.keep(Some(90), write);
        assert_eq!(writes.get(), 3, "switching back on writes again");
    }

    #[test]
    fn failed_write_waits_for_reapply() {
        let writes = Cell::new(0);
        let mut a = Applied::<u8>::default();
        let fail = |_: &u8| {
            writes.set(writes.get() + 1);
            Err("EC busy".to_string())
        };

        a.keep(Some(80), fail);
        a.keep(Some(80), fail);
        assert_eq!(writes.get(), 1);
    }
}

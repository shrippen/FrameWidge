//! Power loop: applies the AC or battery profile (governor, EPP, frequency
//! limits) and switches with the power source.
//!
//! Other tools (power-profiles-daemon, tuned, the Plasma battery applet)
//! may change the same files. A value changed elsewhere is set back only
//! after it stayed unchanged for a while and not right after our own
//! write, so two tools never fight every second. Follows framework-control's
//! `service/src/utils/reconciler.rs` (MIT).

use crate::config::{PowerProfile, Setting};
use crate::App;
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

const TICK: Duration = Duration::from_secs(1);
/// A foreign value must be stable this long before it is overwritten.
const QUIET_WINDOW: Duration = Duration::from_secs(60);
/// Minimum time between two corrections of the same setting.
const COOLDOWN: Duration = Duration::from_secs(120);

type Limits = (Option<u32>, Option<u32>);

pub fn run(app: Arc<App>) {
    let mut governor = Keeper::<String>::default();
    let mut epp = Keeper::<String>::default();
    let mut limits = Keeper::<Limits>::default();

    loop {
        thread::sleep(TICK);

        let Some(on_ac) = app.tool.battery().ok().and_then(|b| b.ac_present) else {
            continue;
        };
        let power = app.config().power;
        let profile = if on_ac { power.ac } else { power.battery }.unwrap_or_default();
        let cpu = &app.cpufreq;

        governor.keep(
            active_text(&profile.governor),
            || cpu.governor(),
            |v| cpu.set_governor(v),
        );
        epp.keep(
            active_text(&profile.epp_preference),
            || cpu.epp(),
            |v| cpu.set_epp(v),
        );

        let wanted = wanted_limits(&profile);
        let masked = |(min, max): (u32, u32)| (wanted.0.map(|_| min), wanted.1.map(|_| max));
        let target = (wanted.0.is_some() || wanted.1.is_some()).then_some(wanted);
        limits.keep(
            target,
            || cpu.limits().map(masked),
            |(min, max)| cpu.set_limits(*min, *max),
        );
    }
}

fn active_text(setting: &Option<Setting<String>>) -> Option<String> {
    setting
        .as_ref()
        .and_then(Setting::active)
        .filter(|v| !v.trim().is_empty())
        .cloned()
}

fn wanted_limits(p: &PowerProfile) -> Limits {
    let pick = |s: &Option<Setting<u32>>| {
        s.as_ref()
            .and_then(Setting::active)
            .copied()
            .filter(|&v| v > 0)
    };
    (pick(&p.min_freq_mhz), pick(&p.max_freq_mhz))
}

/// Keeps one setting at its target.
struct Keeper<T> {
    target: Option<T>,
    seen: Option<T>,
    seen_since: Instant,
    written_at: Option<Instant>,
}

impl<T> Default for Keeper<T> {
    fn default() -> Self {
        Keeper {
            target: None,
            seen: None,
            seen_since: Instant::now(),
            written_at: None,
        }
    }
}

impl<T: PartialEq + Clone + std::fmt::Debug> Keeper<T> {
    /// A new target is written at once; a drifted value only after QUIET_WINDOW
    /// and COOLDOWN. `None` stops keeping (the current value stays).
    fn keep(
        &mut self,
        target: Option<T>,
        read: impl FnOnce() -> Option<T>,
        write: impl FnOnce(&T) -> Result<(), String>,
    ) {
        let Some(target) = target else {
            self.target = None;
            return;
        };

        let now = Instant::now();
        if self.target.as_ref() != Some(&target) {
            if let Err(e) = write(&target) {
                eprintln!("<4>power: {target:?}: {e}");
            }
            self.target = Some(target);
            self.written_at = Some(now);
            return;
        }

        let current = read();
        if current != self.seen {
            self.seen = current.clone();
            self.seen_since = now;
        }
        if current.as_ref() == Some(&target) {
            return;
        }

        let cooling = self
            .written_at
            .is_some_and(|t| now.duration_since(t) < COOLDOWN);
        let settling = current.is_some() && now.duration_since(self.seen_since) < QUIET_WINDOW;
        if cooling || settling {
            return;
        }

        if let Err(e) = write(&target) {
            eprintln!("<4>power: {target:?}: {e}");
        }
        self.written_at = Some(now);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    #[test]
    fn new_target_is_written_at_once_drift_is_not() {
        let writes = RefCell::new(Vec::new());
        let mut k = Keeper::<String>::default();
        let write = |v: &String| {
            writes.borrow_mut().push(v.clone());
            Ok(())
        };

        k.keep(Some("powersave".into()), || None, write);
        assert_eq!(*writes.borrow(), vec!["powersave"]);

        // Another tool switched to performance a moment ago: leave it for now.
        k.keep(
            Some("powersave".into()),
            || Some("performance".into()),
            write,
        );
        assert_eq!(writes.borrow().len(), 1);

        // Once the drift is old and the cooldown passed, set it back.
        k.seen_since -= QUIET_WINDOW;
        k.written_at = k.written_at.map(|t| t - COOLDOWN);
        k.keep(
            Some("powersave".into()),
            || Some("performance".into()),
            write,
        );
        assert_eq!(writes.borrow().len(), 2);
    }

    #[test]
    fn no_target_stops_keeping() {
        let mut k = Keeper::<String>::default();
        k.keep(Some("power".into()), || None, |_| Ok(()));
        k.keep(None, || None, |_| panic!("must not write"));
        assert!(k.target.is_none());
    }

    #[test]
    fn limits_ignore_disabled_and_zero() {
        let p = PowerProfile {
            min_freq_mhz: Some(Setting {
                enabled: false,
                value: 1000,
            }),
            max_freq_mhz: Some(Setting {
                enabled: true,
                value: 3000,
            }),
            ..PowerProfile::default()
        };
        assert_eq!(wanted_limits(&p), (None, Some(3000)));
        assert_eq!(wanted_limits(&PowerProfile::default()), (None, None));
    }
}

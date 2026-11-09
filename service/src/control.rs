//! The one control loop: steps the fans, the charge settings and the
//! history, each at its own interval, and applies a preset when the power
//! source changes. A tick reads the sensors once if a due step needs them
//! (the history, a curve, per-fan manual duties), before any step acts.
//!
//! One loop instead of a thread per task: the steps share one reading,
//! and the order (read, then act) stays fixed.

use crate::battery::Charge;
use crate::config::PowerSource;
use crate::fan::Fans;
use crate::sensors::Thermal;
use crate::App;
use std::thread;
use std::time::{Duration, Instant};

const CHARGE_EVERY: Duration = Duration::from_secs(1);
const TELEMETRY_MIN: Duration = Duration::from_secs(1);
/// Shortest sleep; a curve may ask for 100 ms.
const TICK_MIN: Duration = Duration::from_millis(100);

pub fn run(app: &App) {
    let mut fans = Fans::default();
    let mut charge = Charge::default();
    let mut source: Option<PowerSource> = None;

    let now = Instant::now();
    let (mut fan_due, mut charge_due, mut telemetry_due) = (now, now, now);

    loop {
        let now = Instant::now();

        // The preset switch only reacts to a change, not to the state at
        // start, so a curve chosen by hand stays until the next plug event.
        if let Some(current) = app.power_source() {
            if source.is_some_and(|before| before != current) {
                app.apply_preset_for(current);
            }
            source = Some(current);
        }

        let cfg = app.config();
        let fan_step = now >= fan_due;
        let telemetry_step = now >= telemetry_due;

        // Without the EC hwmon driver a reading is a framework_tool call:
        // read only when a due step uses it, not on every tick.
        let needed = telemetry_step || (fan_step && fans.needs_reading(&cfg.fan));
        let thermal = if needed {
            app.thermal()
        } else {
            Ok(Thermal::default())
        };

        if fan_step {
            let next = match &thermal {
                Ok(t) => fans.step(&app.tool, &cfg.fan, t),
                Err(e) => fans.step_blind(&app.tool, &cfg.fan, e),
            };
            fan_due = now + next;
        }

        if now >= charge_due {
            charge.step(&app.tool, &cfg.battery);
            charge_due = now + CHARGE_EVERY;
        }

        if telemetry_step {
            if let Ok(t) = &thermal {
                app.record(t, cfg.telemetry.retain_seconds);
            }
            telemetry_due = now + Duration::from_millis(cfg.telemetry.poll_ms).max(TELEMETRY_MIN);
        }

        let next = fan_due.min(charge_due).min(telemetry_due);
        thread::sleep(next.saturating_duration_since(Instant::now()).max(TICK_MIN));
    }
}

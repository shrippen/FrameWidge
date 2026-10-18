//! Fan control: manual duty or a temperature curve with hysteresis and
//! rate limits, globally or per fan. The control loop calls `step`.
//!
//! The curve state machine follows framework-control's
//! `service/src/tasks/fan_curve.rs` (MIT).

use crate::config::{Curve, FanConfig, FanMode, PCT_MAX};
use crate::sensors::{self, Thermal};
use crate::tool::{Fan, Tool};
use std::collections::{BTreeMap, HashMap};
use std::time::Duration;

/// Step interval outside curve mode: picks up a changed setting quickly.
pub const IDLE_POLL: Duration = Duration::from_millis(500);

/// Steps without a temperature before a curve hands the fans to the EC.
const BLIND_STEPS: u32 = 3;

#[derive(Default)]
pub struct Fans {
    last: Option<(FanMode, bool)>,
    applied: HashMap<Fan, u32>,
    steppers: HashMap<Fan, Stepper>,
    /// Handing the fans to the EC failed; try again next step.
    auto_pending: bool,
    /// Steps in a row without a temperature reading.
    blind_steps: u32,
}

impl Fans {
    /// One control step; returns when the next one is due.
    pub fn step(&mut self, tool: &Tool, fan: &FanConfig, thermal: &Thermal) -> Duration {
        // A reading without a single temperature (every sensor faulty) is no reading.
        if fan.mode == FanMode::Curve && thermal.temps.is_empty() {
            return self.step_blind(tool, fan, "no sensor reports a temperature");
        }
        self.blind_steps = 0;

        // A new mode or topology starts the curve from the current reading.
        let topology = (fan.mode, !fan.overrides.is_empty());
        let changed = self.last != Some(topology);
        if changed {
            self.applied.clear();
            self.steppers.clear();
        }

        match fan.mode {
            FanMode::Disabled => {
                if changed || self.auto_pending {
                    self.hand_to_ec(tool);
                }
            }
            FanMode::Manual => self.manual(tool, fan, thermal.fans.len(), changed),
            FanMode::Curve => self.curve(tool, fan, thermal),
        }
        self.last = Some(topology);

        match (fan.mode, &fan.curve) {
            (FanMode::Curve, Some(c)) => Duration::from_millis(c.poll_ms),
            _ => IDLE_POLL,
        }
    }

    /// A step without a temperature (`error`: why). Manual and Auto need none.
    /// A curve has nothing to follow: after BLIND_STEPS the EC's own curve
    /// takes over, and the curve starts afresh once readings return.
    pub fn step_blind(&mut self, tool: &Tool, fan: &FanConfig, error: &str) -> Duration {
        if fan.mode != FanMode::Curve {
            return self.step(tool, fan, &Thermal::default());
        }

        self.blind_steps = self.blind_steps.saturating_add(1);
        if self.blind_steps == 1 {
            eprintln!("<4>fan: no temperature: {error}");
        }
        let handover = self.blind_steps == BLIND_STEPS;
        if handover || (self.blind_steps > BLIND_STEPS && self.auto_pending) {
            if handover {
                eprintln!("<4>fan: no temperature; the EC's own curve takes over");
            }
            self.applied.clear();
            self.steppers.clear();
            self.last = None;
            self.hand_to_ec(tool);
        }
        IDLE_POLL
    }

    /// Hands the fans to the EC; a failure is retried on the next step.
    fn hand_to_ec(&mut self, tool: &Tool) {
        let result = tool.auto_fan();
        self.auto_pending = result.is_err();
        log_err(result);
    }

    fn manual(&mut self, tool: &Tool, fan: &FanConfig, fan_count: usize, changed: bool) {
        let global = fan.manual.as_ref().map(|m| m.duty_pct.min(PCT_MAX));

        if fan.overrides.is_empty() {
            match global {
                Some(duty) => self.apply(tool, Fan::All, duty),
                // No duty set: the EC's own curve, not the last duty of another mode.
                None => {
                    if changed || self.auto_pending {
                        self.hand_to_ec(tool);
                    }
                }
            }
            return;
        }

        for i in 0..fan_count as u32 {
            let own = fan
                .overrides
                .iter()
                .find(|o| o.index == i)
                .and_then(|o| o.manual.as_ref());
            let duty = own.map(|m| m.duty_pct.min(PCT_MAX)).or(global);
            if let Some(duty) = duty {
                self.apply(tool, Fan::Index(i), duty);
            }
        }
    }

    fn curve(&mut self, tool: &Tool, fan: &FanConfig, thermal: &Thermal) {
        if fan.overrides.is_empty() {
            let Some(curve) = &fan.curve else {
                return;
            };
            self.follow(tool, Fan::All, curve, &thermal.temps);
            return;
        }

        for i in 0..thermal.fans.len() as u32 {
            let own = fan
                .overrides
                .iter()
                .find(|o| o.index == i)
                .and_then(|o| o.curve.as_ref());
            let Some(curve) = own.or(fan.curve.as_ref()) else {
                continue;
            };
            self.follow(tool, Fan::Index(i), curve, &thermal.temps);
        }
    }

    fn follow(&mut self, tool: &Tool, fan: Fan, curve: &Curve, temps: &BTreeMap<String, i32>) {
        let Some(temp) = sensors::hottest(temps, &curve.sensors) else {
            return;
        };
        let stepper = self.steppers.entry(fan).or_default();
        let Some(duty) = stepper.next(temp, curve) else {
            return;
        };

        match tool.set_fan_duty(fan, duty) {
            Ok(()) => stepper.applied = Some(duty),
            Err(e) => eprintln!("<4>fan {fan:?}: {e}"),
        }
    }

    /// Sets `duty` unless it is already set.
    fn apply(&mut self, tool: &Tool, fan: Fan, duty: u32) {
        if self.applied.get(&fan) == Some(&duty) {
            return;
        }
        match tool.set_fan_duty(fan, duty) {
            Ok(()) => {
                self.applied.insert(fan, duty);
            }
            Err(e) => eprintln!("<4>fan {fan:?}: {e}"),
        }
    }
}

/// Hysteresis and rate-limit state of one fan.
#[derive(Default)]
struct Stepper {
    /// Duty last set on the fan.
    applied: Option<u32>,
    /// Curve duty the fan is heading to.
    target: Option<u32>,
    /// Temperature when `target` was taken; drops are measured from here.
    target_temp: i32,
}

impl Stepper {
    /// Duty to set now, or `None` to keep the current one.
    fn next(&mut self, temp: i32, curve: &Curve) -> Option<u32> {
        let wanted = duty_at(temp, &curve.points);

        // Rising: follow at once. Falling: only once below the hysteresis band.
        let take = match self.target {
            None => true,
            Some(current) if wanted > current => true,
            Some(current) if wanted < current => {
                curve.hysteresis_c == 0
                    || temp >= self.target_temp
                    || temp <= self.target_temp - curve.hysteresis_c as i32
            }
            Some(_) => false,
        };
        if take {
            self.target = Some(wanted);
            self.target_temp = temp;
        }

        let target = self.target?;
        let next = match self.applied {
            None => target,
            Some(prev) if target >= prev => {
                step_toward(prev, target, curve.rate_limit_pct_per_step)
            }
            Some(prev) => step_toward(
                prev,
                target,
                curve
                    .rate_limit_down_pct_per_step
                    .unwrap_or(curve.rate_limit_pct_per_step),
            ),
        };

        (self.applied != Some(next)).then_some(next)
    }
}

/// Linear interpolation over `points`, framed by [0,0] and [100,100].
fn duty_at(temp: i32, points: &[[u32; 2]]) -> u32 {
    let temp = temp as f64;
    let curve: Vec<[u32; 2]> = [[0, 0]]
        .into_iter()
        .chain(points.iter().copied())
        .chain([[100, 100]])
        .collect();

    for pair in curve.windows(2) {
        let (x1, y1) = (pair[0][0] as f64, pair[0][1] as f64);
        let (x2, y2) = (pair[1][0] as f64, pair[1][1] as f64);

        if temp <= x1 {
            return y1 as u32;
        }
        if temp > x2 {
            continue;
        }
        if x2 == x1 {
            return y2 as u32;
        }
        return (y1 + (temp - x1) / (x2 - x1) * (y2 - y1)).round() as u32;
    }

    PCT_MAX
}

fn step_toward(current: u32, target: u32, max_step: u32) -> u32 {
    if target > current {
        current.saturating_add(max_step).min(target)
    } else {
        current.saturating_sub(max_step).max(target)
    }
}

fn log_err(result: Result<(), String>) {
    if let Err(e) = result {
        eprintln!("<4>fan: {e}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn curve(points: Vec<[u32; 2]>, hysteresis_c: u32, rate: u32) -> Curve {
        Curve {
            points,
            hysteresis_c,
            rate_limit_pct_per_step: rate,
            ..Curve::default()
        }
    }

    #[test]
    fn interpolates_between_implied_anchors() {
        let points = [[40, 20], [60, 40], [75, 80]];
        assert_eq!(duty_at(0, &points), 0);
        assert_eq!(duty_at(20, &points), 10);
        assert_eq!(duty_at(50, &points), 30);
        assert_eq!(duty_at(87, &points), 90);
        assert_eq!(duty_at(100, &points), 100);
        assert_eq!(duty_at(120, &points), 100);
        assert_eq!(duty_at(50, &[]), 50);
    }

    #[test]
    fn rate_limit_steps() {
        assert_eq!(step_toward(30, 50, 10), 40);
        assert_eq!(step_toward(30, 35, 10), 35);
        assert_eq!(step_toward(50, 30, 10), 40);
        assert_eq!(step_toward(30, 80, 100), 80);
    }

    #[test]
    fn stepper_applies_once_then_holds() {
        let c = curve(vec![[40, 20], [60, 40]], 0, 100);
        let mut s = Stepper::default();
        assert_eq!(s.next(50, &c), Some(30));
        s.applied = Some(30);
        assert_eq!(s.next(50, &c), None);
    }

    #[test]
    fn stepper_hysteresis_holds_small_drops() {
        let c = curve(vec![[40, 20], [60, 40]], 5, 100);
        let mut s = Stepper::default();
        assert_eq!(s.next(60, &c), Some(40));
        s.applied = Some(40);
        assert_eq!(s.next(58, &c), None, "2 °C drop is inside the 5 °C band");
        assert_eq!(s.next(54, &c), Some(34));
    }

    #[test]
    fn stepper_rises_at_once_within_rate_limit() {
        let c = curve(vec![[40, 20], [60, 80]], 0, 10);
        let mut s = Stepper {
            applied: Some(20),
            ..Stepper::default()
        };
        assert_eq!(s.next(60, &c), Some(30));
    }

    #[test]
    fn stepper_separate_down_rate() {
        let mut c = curve(vec![[40, 20], [60, 80]], 0, 100);
        c.rate_limit_down_pct_per_step = Some(5);
        let mut s = Stepper {
            applied: Some(80),
            ..Stepper::default()
        };
        assert_eq!(s.next(40, &c), Some(75));
    }
}

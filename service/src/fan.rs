//! Fan control loop: manual duty or a temperature curve with hysteresis
//! and rate limits, globally or per fan.
//!
//! The curve state machine follows framework-control's
//! `service/src/tasks/fan_curve.rs` (MIT).

use crate::config::{Curve, FanMode, PCT_MAX};
use crate::tool::{Fan, Tool};
use crate::App;
use std::collections::{BTreeMap, HashMap};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

const IDLE_POLL: Duration = Duration::from_millis(500);

pub fn run(app: Arc<App>) {
    let mut ctl = Controller::default();

    loop {
        let started = Instant::now();
        let fan = app.config().fan;

        // A new mode or topology starts the curve from the current reading.
        let topology = (fan.mode, !fan.overrides.is_empty());
        if ctl.last != Some(topology) {
            ctl.reset();
        }

        let poll = match fan.mode {
            FanMode::Curve => fan
                .curve
                .as_ref()
                .map_or(IDLE_POLL, |c| Duration::from_millis(c.poll_ms)),
            _ => IDLE_POLL,
        };

        match fan.mode {
            FanMode::Disabled => {
                if ctl.last != Some(topology) {
                    log_err(app.tool.auto_fan());
                }
            }
            FanMode::Manual => ctl.manual(&app.tool, &fan),
            FanMode::Curve => ctl.curve(&app.tool, &fan),
        }
        ctl.last = Some(topology);

        thread::sleep(poll.saturating_sub(started.elapsed()));
    }
}

#[derive(Default)]
struct Controller {
    last: Option<(FanMode, bool)>,
    applied: HashMap<Fan, u32>,
    steppers: HashMap<Fan, Stepper>,
    fan_count: Option<u32>,
}

impl Controller {
    fn reset(&mut self) {
        self.applied.clear();
        self.steppers.clear();
        self.fan_count = None;
    }

    fn manual(&mut self, tool: &Tool, fan: &crate::config::FanConfig) {
        let global = fan.manual.as_ref().map(|m| m.duty_pct.min(PCT_MAX));

        if fan.overrides.is_empty() {
            match global {
                Some(duty) => self.apply(tool, Fan::All, duty),
                None => {
                    if self.last.is_none() {
                        log_err(tool.auto_fan());
                    }
                }
            }
            return;
        }

        let Some(count) = self.count(tool) else {
            return;
        };
        for i in 0..count {
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

    fn curve(&mut self, tool: &Tool, fan: &crate::config::FanConfig) {
        let temps = match tool.thermal() {
            Ok(t) => t.temps,
            Err(e) => return eprintln!("<4>fan: {e}"),
        };

        if fan.overrides.is_empty() {
            let Some(curve) = &fan.curve else {
                return;
            };
            self.step(tool, Fan::All, curve, &temps);
            return;
        }

        let Some(count) = self.count(tool) else {
            return;
        };
        for i in 0..count {
            let own = fan
                .overrides
                .iter()
                .find(|o| o.index == i)
                .and_then(|o| o.curve.as_ref());
            let Some(curve) = own.or(fan.curve.as_ref()) else {
                continue;
            };
            self.step(tool, Fan::Index(i), curve, &temps);
        }
    }

    fn step(&mut self, tool: &Tool, fan: Fan, curve: &Curve, temps: &BTreeMap<String, i32>) {
        let Some(temp) = hottest(temps, &curve.sensors) else {
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

    fn count(&mut self, tool: &Tool) -> Option<u32> {
        if self.fan_count.is_none() {
            // Zero fans means the EC was not ready; ask again next tick.
            let n = tool.thermal().ok()?.fans.len() as u32;
            self.fan_count = (n > 0).then_some(n);
        }
        self.fan_count
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

/// Hottest of `sensors` (exact, then case-insensitive). If none of them
/// exists, e.g. after an EC update renamed the sensors, the hottest of all,
/// so the fan never stays on a stale reading.
fn hottest(temps: &BTreeMap<String, i32>, sensors: &[String]) -> Option<i32> {
    let picked = sensors
        .iter()
        .filter_map(|name| {
            temps.get(name).or_else(|| {
                temps
                    .iter()
                    .find(|(k, _)| k.eq_ignore_ascii_case(name))
                    .map(|(_, v)| v)
            })
        })
        .max()
        .copied();

    picked.or_else(|| temps.values().max().copied())
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

    #[test]
    fn hottest_falls_back_only_without_any_match() {
        let temps: BTreeMap<String, i32> = [
            ("apu_f75303@4d".to_string(), 58),
            ("cpu@4c".to_string(), 62),
        ]
        .into();
        assert_eq!(hottest(&temps, &["APU".to_string()]), Some(62));
        assert_eq!(
            hottest(&temps, &["APU_F75303@4D".to_string(), "gpu".to_string()]),
            Some(58)
        );
        assert_eq!(hottest(&BTreeMap::new(), &[]), None);
    }
}

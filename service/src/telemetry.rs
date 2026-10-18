//! Telemetry loop: keeps the recent temperatures and fan speeds for the
//! widget's sensor graph (`/api/thermal/history`).

use crate::App;
use serde::Serialize;
use std::collections::{BTreeMap, VecDeque};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const POLL_MIN_MS: u64 = 1000;
const MS_PER_S: i64 = 1000;

#[derive(Debug, Clone, Serialize)]
pub struct Sample {
    pub ts_ms: i64,
    pub temps: BTreeMap<String, i32>,
    pub rpms: Vec<u32>,
}

pub fn run(app: Arc<App>) {
    loop {
        let cfg = app.config().telemetry;

        match app.tool.thermal() {
            Ok(t) => {
                let sample = Sample {
                    ts_ms: now_ms(),
                    temps: t.temps,
                    rpms: t.fans.iter().map(|f| f.rpm).collect(),
                };
                let mut history = app.history.lock().unwrap_or_else(|e| e.into_inner());
                push(&mut history, sample, cfg.retain_seconds);
            }
            Err(e) => eprintln!("<4>telemetry: {e}"),
        }

        thread::sleep(Duration::from_millis(cfg.poll_ms.max(POLL_MIN_MS)));
    }
}

/// Appends `sample` and drops what is older than `retain_seconds`.
fn push(history: &mut VecDeque<Sample>, sample: Sample, retain_seconds: u64) {
    let cutoff = sample.ts_ms - retain_seconds as i64 * MS_PER_S;
    history.push_back(sample);
    while history.front().is_some_and(|s| s.ts_ms < cutoff) {
        history.pop_front();
    }
}

pub fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(ts_ms: i64) -> Sample {
        Sample {
            ts_ms,
            temps: BTreeMap::new(),
            rpms: Vec::new(),
        }
    }

    #[test]
    fn drops_samples_past_retention() {
        let mut h = VecDeque::new();
        push(&mut h, at(0), 10);
        push(&mut h, at(5_000), 10);
        push(&mut h, at(12_000), 10);
        let kept: Vec<i64> = h.iter().map(|s| s.ts_ms).collect();
        assert_eq!(kept, vec![5_000, 12_000]);
    }
}

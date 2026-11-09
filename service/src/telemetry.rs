//! Recent temperatures and fan speeds for the widget's sensor graph
//! (`ThermalHistory`). The control loop records; D-Bus calls read.

use crate::sensors::Thermal;
use serde::Serialize;
use std::collections::{BTreeMap, VecDeque};
use std::time::{SystemTime, UNIX_EPOCH};

const MS_PER_S: i64 = 1000;

#[derive(Debug, Clone, Serialize)]
pub struct Sample {
    pub ts_ms: i64,
    pub temps: BTreeMap<String, i32>,
    pub rpms: Vec<u32>,
}

#[derive(Default)]
pub struct History {
    samples: VecDeque<Sample>,
}

impl History {
    /// Appends a reading and drops what is older than `retain_seconds`.
    pub fn record(&mut self, thermal: &Thermal, retain_seconds: u64) {
        let sample = Sample {
            ts_ms: now_ms(),
            temps: thermal.temps.clone(),
            rpms: thermal.fans.iter().map(|f| f.rpm).collect(),
        };
        self.push(sample, retain_seconds);
    }

    pub fn samples(&self) -> Vec<Sample> {
        self.samples.iter().cloned().collect()
    }

    /// Samples newer than `since_ms`, oldest first.
    pub fn since(&self, since_ms: i64) -> Vec<Sample> {
        self.samples
            .iter()
            .filter(|s| s.ts_ms > since_ms)
            .cloned()
            .collect()
    }

    /// Keeps the samples in order: after the clock was set back, the ones
    /// now in the future go, or every `since` would send them again.
    fn push(&mut self, sample: Sample, retain_seconds: u64) {
        while self.samples.back().is_some_and(|s| s.ts_ms > sample.ts_ms) {
            self.samples.pop_back();
        }
        let cutoff = sample.ts_ms - retain_seconds as i64 * MS_PER_S;
        self.samples.push_back(sample);
        while self.samples.front().is_some_and(|s| s.ts_ms < cutoff) {
            self.samples.pop_front();
        }
    }
}

fn now_ms() -> i64 {
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
        let mut h = History::default();
        h.push(at(0), 10);
        h.push(at(5_000), 10);
        h.push(at(12_000), 10);
        let kept: Vec<i64> = h.samples().iter().map(|s| s.ts_ms).collect();
        assert_eq!(kept, vec![5_000, 12_000]);
    }

    #[test]
    fn clock_set_back_drops_the_samples_ahead() {
        // Dual boot with the RTC in local time, then NTP: the samples taken
        // before are now in the future. Kept, every ThermalHistorySince
        // would send them again until the clock passes them.
        let mut h = History::default();
        for ts in [10_000, 20_000, 30_000] {
            h.push(at(ts), 3600);
        }
        h.push(at(15_000), 3600);
        let kept: Vec<i64> = h.samples().iter().map(|s| s.ts_ms).collect();
        assert_eq!(kept, vec![10_000, 15_000]);
        assert!(h.since(15_000).is_empty());
    }

    #[test]
    fn since_returns_only_newer_samples() {
        let mut h = History::default();
        for ts in [1_000, 2_000, 3_000] {
            h.push(at(ts), 3600);
        }
        let ts = |v: Vec<Sample>| v.iter().map(|s| s.ts_ms).collect::<Vec<_>>();
        assert_eq!(ts(h.since(2_000)), vec![3_000]);
        assert_eq!(ts(h.since(0)), vec![1_000, 2_000, 3_000]);
        assert!(h.since(3_000).is_empty());
    }
}

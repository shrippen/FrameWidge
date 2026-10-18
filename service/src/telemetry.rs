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

    fn push(&mut self, sample: Sample, retain_seconds: u64) {
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
}

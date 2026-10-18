//! Client for power-profiles-daemon (or tuned-ppd): the system's power
//! profile (power-saver, balanced, performance). That daemon owns governor,
//! EPP and platform profile; Plasma's battery applet switches it too. This
//! service only reads and sets the profile, so nothing fights over cpufreq.

use serde::Serialize;
use std::collections::HashMap;
use zbus::proxy::CacheProperties;
use zbus::zvariant::OwnedValue;
use zbus::Connection;

/// Current name first, then the one of power-profiles-daemon before 0.20.
const DAEMONS: [(&str, &str); 2] = [
    (
        "org.freedesktop.UPower.PowerProfiles",
        "/org/freedesktop/UPower/PowerProfiles",
    ),
    ("net.hadess.PowerProfiles", "/net/hadess/PowerProfiles"),
];

#[derive(Debug, Serialize)]
pub struct Profiles {
    pub active: String,
    pub available: Vec<String>,
}

/// `None` when no profile daemon runs.
pub async fn read(conn: &Connection) -> Option<Profiles> {
    for (name, path) in DAEMONS {
        let Ok(proxy) = proxy(conn, name, path).await else {
            continue;
        };
        let Ok(active) = proxy.get_property::<String>("ActiveProfile").await else {
            continue;
        };
        let listed: Vec<HashMap<String, OwnedValue>> =
            proxy.get_property("Profiles").await.unwrap_or_default();
        let available = listed
            .iter()
            .filter_map(|p| String::try_from(p.get("Profile")?.try_clone().ok()?).ok())
            .collect();
        return Some(Profiles { active, available });
    }
    None
}

pub async fn set(conn: &Connection, profile: &str) -> Result<(), String> {
    let current = read(conn).await.ok_or("no power profile daemon")?;
    if !current.available.iter().any(|p| p == profile) {
        return Err(format!(
            "unknown profile {profile}; available: {:?}",
            current.available
        ));
    }

    for (name, path) in DAEMONS {
        let Ok(proxy) = proxy(conn, name, path).await else {
            continue;
        };
        if proxy.set_property("ActiveProfile", profile).await.is_ok() {
            return Ok(());
        }
    }
    Err("setting the power profile failed".into())
}

async fn proxy<'a>(
    conn: &Connection,
    name: &'a str,
    path: &'a str,
) -> zbus::Result<zbus::Proxy<'a>> {
    zbus::proxy::Builder::new(conn)
        .destination(name)?
        .path(path)?
        .interface(name)?
        .cache_properties(CacheProperties::No)
        .build()
        .await
}

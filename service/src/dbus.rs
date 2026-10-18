//! D-Bus interface for the widget, on the system bus.
//!
//! Replies are JSON strings in the schema the widget already uses (see
//! DESIGN.md): one stable D-Bus signature, the schema evolves in JSON.
//! Reading is open to every local user; changing settings asks polkit
//! (action CONFIGURE_ACTION: yes for the active local session, else an
//! admin password). On the session bus (tests) there is no polkit check.

use crate::{profiles, system, App};
use serde::Serialize;
use serde_json::json;
use std::collections::HashMap;
use std::sync::Arc;
use zbus::fdo::{Error, Result};
use zbus::message::Header;
use zbus::zvariant::Value;
use zbus::{interface, Connection};

pub const BUS_NAME: &str = "io.github.shrippen.FrameWidge";
pub const OBJECT_PATH: &str = "/io/github/shrippen/FrameWidge";
const CONFIGURE_ACTION: &str = "io.github.shrippen.FrameWidge.configure";
/// polkit CheckAuthorization flag: may show a password dialog.
const ALLOW_USER_INTERACTION: u32 = 1;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Auth {
    Polkit,
    /// Session bus: only the user's own processes can call.
    Open,
}

pub struct Service {
    pub app: Arc<App>,
    pub auth: Auth,
}

#[interface(name = "io.github.shrippen.FrameWidge1")]
impl Service {
    fn health(&self) -> String {
        json!({
            "cli_present": self.app.tool.present(),
            "service_version": env!("CARGO_PKG_VERSION"),
        })
        .to_string()
    }

    async fn thermal(&self) -> Result<String> {
        let app = Arc::clone(&self.app);
        to_json(
            &blocking::unblock(move || app.thermal())
                .await
                .map_err(Error::Failed)?,
        )
    }

    fn thermal_history(&self) -> Result<String> {
        to_json(&self.app.history())
    }

    /// Battery and charger, the EC's charge limit, and the power profile.
    async fn power(&self, #[zbus(connection)] conn: &Connection) -> Result<String> {
        let app = Arc::clone(&self.app);
        let (battery, limit) =
            blocking::unblock(move || (app.battery(), app.tool.charge_limit().ok())).await;

        let mut battery = serde_json::to_value(battery).map_err(fail)?;
        if let (Some(obj), Some(Ok(serde_json::Value::Object(limit)))) =
            (battery.as_object_mut(), limit.map(serde_json::to_value))
        {
            obj.extend(limit);
        }

        let profile = profiles::read(conn).await;
        Ok(json!({ "battery": battery, "profile": profile }).to_string())
    }

    async fn set_power_profile(
        &self,
        #[zbus(header)] header: Header<'_>,
        #[zbus(connection)] conn: &Connection,
        profile: String,
    ) -> Result<()> {
        self.authorize(conn, &header).await?;
        profiles::set(conn, &profile)
            .await
            .map_err(Error::InvalidArgs)
    }

    async fn versions(&self) -> Result<String> {
        let app = Arc::clone(&self.app);
        to_json(
            &blocking::unblock(move || app.tool.versions())
                .await
                .map_err(Error::Failed)?,
        )
    }

    fn system(&self) -> Result<String> {
        to_json(&system::info())
    }

    fn config(&self) -> Result<String> {
        to_json(&self.app.config())
    }

    /// `patch`: JSON object, merged into the config (see config.rs). Returns the new config.
    async fn set_config(
        &self,
        #[zbus(header)] header: Header<'_>,
        #[zbus(connection)] conn: &Connection,
        patch: String,
    ) -> Result<String> {
        self.authorize(conn, &header).await?;
        let patch: serde_json::Value =
            serde_json::from_str(&patch).map_err(|e| Error::InvalidArgs(e.to_string()))?;
        // Saving writes a file; keep it off the D-Bus executor.
        let app = Arc::clone(&self.app);
        let cfg = blocking::unblock(move || app.update_config(&patch))
            .await
            .map_err(Error::InvalidArgs)?;
        to_json(&cfg)
    }

    async fn logs(&self) -> Result<String> {
        blocking::unblock(system::logs).await.map_err(Error::Failed)
    }
}

impl Service {
    async fn authorize(&self, conn: &Connection, header: &Header<'_>) -> Result<()> {
        if self.auth == Auth::Open {
            return Ok(());
        }
        let sender = header
            .sender()
            .ok_or_else(|| Error::AccessDenied("no sender".into()))?;

        match polkit_allows(conn, sender.as_str()).await {
            Ok(true) => Ok(()),
            Ok(false) => Err(Error::AccessDenied(
                "not authorized to change FrameWidge settings".into(),
            )),
            Err(e) => Err(Error::AccessDenied(format!("polkit: {e}"))),
        }
    }
}

/// Asks polkit whether bus client `sender` may run CONFIGURE_ACTION.
async fn polkit_allows(conn: &Connection, sender: &str) -> zbus::Result<bool> {
    let subject = (
        "system-bus-name",
        HashMap::from([("name", Value::from(sender))]),
    );
    let details: HashMap<&str, &str> = HashMap::new();
    let reply = conn
        .call_method(
            Some("org.freedesktop.PolicyKit1"),
            "/org/freedesktop/PolicyKit1/Authority",
            Some("org.freedesktop.PolicyKit1.Authority"),
            "CheckAuthorization",
            &(
                subject,
                CONFIGURE_ACTION,
                details,
                ALLOW_USER_INTERACTION,
                "",
            ),
        )
        .await?;

    // One struct (bba{ss}): is_authorized, is_challenge, details.
    let (authorized, _challenge, _details): (bool, bool, HashMap<String, String>) =
        reply.body().deserialize()?;
    Ok(authorized)
}

fn to_json<T: Serialize>(value: &T) -> Result<String> {
    serde_json::to_string(value).map_err(fail)
}

fn fail(e: serde_json::Error) -> Error {
    Error::Failed(e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{BufRead, BufReader};
    use std::process::{Command, Stdio};
    use zbus::zvariant::Type;

    /// CheckAuthorization's reply: one struct, as real polkit sends it.
    #[derive(serde::Serialize, Type)]
    struct AuthResult(bool, bool, HashMap<String, String>);

    struct FakeAuthority {
        allow: bool,
    }

    #[interface(name = "org.freedesktop.PolicyKit1.Authority")]
    impl FakeAuthority {
        fn check_authorization(
            &self,
            subject: (String, HashMap<String, zbus::zvariant::OwnedValue>),
            action_id: String,
            _details: HashMap<String, String>,
            flags: u32,
            _cancellation_id: String,
        ) -> AuthResult {
            let named = subject.0 == "system-bus-name" && subject.1.contains_key("name");
            let ok = named && action_id == CONFIGURE_ACTION && flags == ALLOW_USER_INTERACTION;
            AuthResult(self.allow && ok, false, HashMap::new())
        }
    }

    fn ask(allow: bool) -> zbus::Result<bool> {
        let mut bus = Command::new("dbus-daemon")
            .args(["--session", "--nofork", "--print-address=1"])
            .arg(format!(
                "--address=unix:tmpdir={}",
                std::env::temp_dir().display()
            ))
            .stdout(Stdio::piped())
            .spawn()
            .expect("dbus-daemon");
        let mut address = String::new();
        BufReader::new(bus.stdout.take().unwrap())
            .read_line(&mut address)
            .unwrap();

        let result = zbus::block_on(async {
            let _polkit = zbus::connection::Builder::address(address.trim())?
                .name("org.freedesktop.PolicyKit1")?
                .serve_at(
                    "/org/freedesktop/PolicyKit1/Authority",
                    FakeAuthority { allow },
                )?
                .build()
                .await?;
            let client = zbus::connection::Builder::address(address.trim())?
                .build()
                .await?;
            polkit_allows(&client, ":1.42").await
        });

        let _ = bus.kill();
        let _ = bus.wait();
        result
    }

    #[test]
    fn reads_polkit_answer() {
        assert!(ask(true).unwrap());
        assert!(!ask(false).unwrap());
    }
}

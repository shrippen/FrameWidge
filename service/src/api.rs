//! REST API on 127.0.0.1 for the widget (schema in DESIGN.md).
//!
//! Every local process can reach the port, web pages in a browser too.
//! Two checks keep pages out: a POST must be `application/json` (a page
//! cannot send that cross-site without a CORS preflight, which is never
//! answered), and the Host header must name the loopback address (a page
//! behind a DNS name rebound to 127.0.0.1 sends its own name).

use crate::{system, App};
use serde::Serialize;
use serde_json::{json, Value};
use std::io::Read;
use std::sync::Arc;
use std::thread;
use tiny_http::{Header, Method, Request, Response, Server};

const MAX_BODY: u64 = 64 * 1024;
const LOOPBACK_HOSTS: [&str; 3] = ["127.0.0.1", "localhost", "[::1]"];

const OK: u16 = 200;
const BAD_REQUEST: u16 = 400;
const FORBIDDEN: u16 = 403;
const NOT_FOUND: u16 = 404;
const UNSUPPORTED_MEDIA: u16 = 415;
const INTERNAL_ERROR: u16 = 500;
const BAD_GATEWAY: u16 = 502;

type Reply = (u16, Body);

enum Body {
    Json(Value),
    Text(String),
}

pub fn serve(app: Arc<App>, server: Server) {
    for request in server.incoming_requests() {
        let app = Arc::clone(&app);
        // framework_tool calls take up to a second; one slow call must not stall the rest.
        thread::spawn(move || handle(&app, request));
    }
}

fn handle(app: &App, mut request: Request) {
    let (status, body) = route(app, &mut request);

    let (data, content_type) = match body {
        Body::Json(v) => (v.to_string(), "application/json"),
        Body::Text(t) => (t, "text/plain; charset=utf-8"),
    };
    let header = Header::from_bytes("Content-Type", content_type).expect("static header");
    let _ = request.respond(
        Response::from_string(data)
            .with_status_code(status)
            .with_header(header),
    );
}

fn route(app: &App, request: &mut Request) -> Reply {
    if !loopback_host(request, app.port) {
        return error(FORBIDDEN, "host not allowed");
    }

    let path = request
        .url()
        .split('?')
        .next()
        .unwrap_or_default()
        .to_string();
    match (request.method(), path.as_str()) {
        (Method::Get, "/api/health") => json_ok(json!({
            "cli_present": app.tool.present(),
            "service_version": env!("CARGO_PKG_VERSION"),
            "service": system::UNIT,
        })),
        (Method::Get, "/api/thermal") => from_tool(app.tool.thermal()),
        (Method::Get, "/api/thermal/history") => {
            let history = app.history.lock().unwrap_or_else(|e| e.into_inner());
            to_json(&history.iter().collect::<Vec<_>>())
        }
        (Method::Get, "/api/power") => power(app),
        (Method::Get, "/api/versions") => from_tool(app.tool.versions()),
        (Method::Get, "/api/system") => to_json(&system::info()),
        (Method::Get, "/api/config") => to_json(&app.config()),
        (Method::Post, "/api/config") => set_config(app, request),
        (Method::Get, "/api/logs") => match system::logs() {
            Ok(text) => (OK, Body::Text(text)),
            Err(e) => error(INTERNAL_ERROR, &e),
        },
        _ => error(NOT_FOUND, "no such endpoint"),
    }
}

fn power(app: &App) -> Reply {
    let battery = match app.tool.battery() {
        Ok(b) => b,
        Err(e) => return error(BAD_GATEWAY, &e),
    };

    // Battery facts and the EC's charge limit form one object, as the widget expects.
    let mut battery = serde_json::to_value(battery).unwrap_or_default();
    if let (Some(obj), Ok(limit)) = (battery.as_object_mut(), app.tool.charge_limit()) {
        if let Ok(Value::Object(limit)) = serde_json::to_value(limit) {
            obj.extend(limit);
        }
    }

    json_ok(json!({
        "battery": battery,
        "power_control": {
            "capabilities": app.cpufreq.capabilities(),
            "current_state": app.cpufreq.state(),
        }
    }))
}

fn set_config(app: &App, request: &mut Request) -> Reply {
    let is_json = request
        .headers()
        .iter()
        .any(|h| h.field.equiv("Content-Type") && h.value.as_str().starts_with("application/json"));
    if !is_json {
        return error(UNSUPPORTED_MEDIA, "Content-Type must be application/json");
    }

    let mut text = String::new();
    if let Err(e) = request.as_reader().take(MAX_BODY).read_to_string(&mut text) {
        return error(BAD_REQUEST, &e.to_string());
    }
    let patch: Value = match serde_json::from_str(&text) {
        Ok(v) => v,
        Err(e) => return error(BAD_REQUEST, &e.to_string()),
    };

    match app.update_config(&patch) {
        Ok(cfg) => to_json(&cfg),
        Err(e) => error(BAD_REQUEST, &e),
    }
}

/// Host header is a loopback name with our port.
fn loopback_host(request: &Request, port: u16) -> bool {
    let Some(host) = request.headers().iter().find(|h| h.field.equiv("Host")) else {
        return false;
    };
    let host = host.value.as_str();
    LOOPBACK_HOSTS
        .iter()
        .any(|name| host == *name || host == format!("{name}:{port}"))
}

fn from_tool<T: Serialize>(result: Result<T, String>) -> Reply {
    match result {
        Ok(v) => to_json(&v),
        Err(e) => error(BAD_GATEWAY, &e),
    }
}

fn to_json<T: Serialize>(value: &T) -> Reply {
    match serde_json::to_value(value) {
        Ok(v) => json_ok(v),
        Err(e) => error(INTERNAL_ERROR, &e.to_string()),
    }
}

fn json_ok(value: Value) -> Reply {
    (OK, Body::Json(value))
}

fn error(status: u16, message: &str) -> Reply {
    (status, Body::Json(json!({ "error": message })))
}

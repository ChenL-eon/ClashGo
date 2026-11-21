use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use serde_json::{json, Value};

use super::build;
use super::model::{AppState, BuildRequest, Override, Platform};

static COUNTER: AtomicU64 = AtomicU64::new(0);

struct TempDir(PathBuf);

impl TempDir {
    fn new() -> Self {
        let id = COUNTER.fetch_add(1, Ordering::Relaxed);
        let path =
            std::env::temp_dir().join(format!("stelliberty-rust-{}-{id}", std::process::id()));
        fs::create_dir_all(&path).expect("create temp dir");
        Self(path)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn platform() -> Platform {
    Platform {
        vpn_tun_mtu: 9000,
        default_mixed_port: 7890,
        root_tproxy_port: 7895,
        root_tether_tproxy_port: 7895,
        root_dns_port: 1053,
        root_tun_table_index: 2022,
        root_tun_rule_index: 9000,
        intranet_routes_v4: vec!["10.0.0.0/8".to_string(), "192.168.0.0/16".to_string()],
        intranet_routes_v6: vec!["fe80::/10".to_string()],
    }
}

fn app() -> AppState {
    AppState {
        self_package: "com.stelliberty.android".to_string(),
        app_proxy_mode: "AllowAll".to_string(),
        app_proxy_packages: Vec::new(),
        allow_ipv6: false,
        root_tun_device: "Stelliberty".to_string(),
        root_tun_jumbo_mtu: true,
    }
}

fn request(dir: &Path, mode: &str) -> BuildRequest {
    BuildRequest {
        work_dir: dir.display().to_string(),
        tun_mode: mode.to_string(),
        tun_fd: 77,
        mixed_port_required: false,
        subscription_mixed_port: None,
        tproxy_for_tether: false,
        wifi_runtime_mode: None,
        user_override: Override::default(),
        platform: platform(),
        app: app(),
    }
}

fn build_json(request: &BuildRequest) -> Value {
    let outcome = build(request).expect("build runtime override");
    let raw = fs::read_to_string(&outcome.path).expect("read override.run.json");
    serde_json::from_str(&raw).expect("override.run.json is valid JSON")
}

#[test]
fn vpn_mode_writes_runner_override_without_controller() {
    let dir = TempDir::new();
    let req = request(dir.path(), "vpn");
    let merged = build_json(&req);

    assert_eq!(merged["tun"]["enable"], json!(true));
    assert_eq!(merged["tun"]["auto-route"], json!(false));
    assert_eq!(merged["tun"]["auto-detect-interface"], json!(false));
    assert_eq!(merged["tun"]["file-descriptor"], json!(77));
    assert_eq!(merged["tun"]["inet6-address"], json!([]));
    assert_eq!(merged["tun"]["dns-hijack"], json!(["0.0.0.0:53"]));
    assert_eq!(merged["tun"]["mtu"], json!(9000));
    assert!(merged["tun"].get("gso").is_none());
    assert!(merged["tun"].get("route-exclude-address").is_none());
    assert!(merged["tun"].get("include-package").is_none());
    assert!(merged.get("external-controller").is_none());
    assert!(merged.get("secret").is_none());
    assert!(merged.get("mixed-port").is_none());
    assert_eq!(merged["tcp-concurrent"], json!(true));
    assert_eq!(merged["find-process-mode"], json!("off"));
    assert_eq!(merged["profile"]["store-selected"], json!(false));
    assert_eq!(merged["profile"]["store-fake-ip"], json!(true));
}

#[test]
fn root_tun_defaults_to_jumbo_and_intranet_exclusions() {
    let dir = TempDir::new();
    let mut req = request(dir.path(), "root_tun");
    req.app.allow_ipv6 = true;
    let merged = build_json(&req);

    assert_eq!(merged["tun"]["auto-route"], json!(true));
    assert_eq!(merged["tun"]["auto-detect-interface"], json!(true));
    assert!(merged["tun"].get("file-descriptor").is_none());
    assert_eq!(
        merged["tun"]["inet6-address"],
        json!(["fdfe:dcba:9876::1/126"])
    );
    assert_eq!(
        merged["tun"]["route-exclude-address"],
        json!(["10.0.0.0/8", "192.168.0.0/16", "fe80::/10"])
    );
    assert_eq!(merged["tun"]["device"], json!("Stelliberty"));
    assert_eq!(merged["tun"]["mtu"], json!(9000));
    assert_eq!(merged["tun"]["gso"], json!(true));
    assert_eq!(merged["tun"]["gso-max-size"], json!(65535));
    assert_eq!(merged["tun"]["iproute2-table-index"], json!(2022));
    assert_eq!(merged["tun"]["iproute2-rule-index"], json!(9000));
    assert_eq!(
        merged["tun"]["exclude-package"],
        json!(["com.stelliberty.android"])
    );
    assert_eq!(merged["dns"]["enable"], json!(true));
    assert_eq!(merged["dns"]["listen"], json!("0.0.0.0:1053"));
    assert_eq!(merged["dns"]["enhanced-mode"], json!("redir-host"));
    assert!(merged.get("tproxy-port").is_none());
}

#[test]
fn root_tun_without_jumbo_or_ipv6_falls_back_to_plain_mtu() {
    let dir = TempDir::new();
    let mut req = request(dir.path(), "root_tun");
    req.app.root_tun_jumbo_mtu = false;
    let merged = build_json(&req);

    assert_eq!(merged["tun"]["mtu"], json!(1500));
    assert_eq!(merged["tun"]["gso"], json!(false));
    assert!(merged["tun"].get("gso-max-size").is_none());
    assert!(merged["tun"].get("inet6-address").is_none());
    assert_eq!(
        merged["tun"]["route-exclude-address"],
        json!(["10.0.0.0/8", "192.168.0.0/16"])
    );
}

#[test]
fn root_tproxy_disables_tun_and_pins_proxy_port() {
    let dir = TempDir::new();
    let mut req = request(dir.path(), "root_tproxy");
    req.user_override.tproxy_port = Some(1234);
    let merged = build_json(&req);

    assert_eq!(merged["tun"], json!({ "enable": false }));
    assert_eq!(merged["tproxy-port"], json!(7895));
    assert_eq!(merged["dns"]["listen"], json!("0.0.0.0:1053"));
}

#[test]
fn root_tun_tether_pins_shared_tproxy_port() {
    let dir = TempDir::new();
    let mut req = request(dir.path(), "root_tun");
    req.user_override.tproxy_port = Some(1234);
    req.tproxy_for_tether = true;
    let merged = build_json(&req);

    assert_eq!(merged["tproxy-port"], json!(7895));
}

#[test]
fn mixed_port_precedence_matches_kotlin() {
    let dir = TempDir::new();

    let mut req = request(dir.path(), "vpn");
    req.user_override.mixed_port = Some(0);
    req.subscription_mixed_port = Some(7891);
    req.mixed_port_required = true;
    assert_eq!(build_json(&req)["mixed-port"], json!(0));

    let mut req = request(dir.path(), "vpn");
    req.subscription_mixed_port = Some(7891);
    req.mixed_port_required = true;
    assert!(build_json(&req).get("mixed-port").is_none());

    let mut req = request(dir.path(), "vpn");
    req.mixed_port_required = true;
    assert_eq!(build_json(&req)["mixed-port"], json!(7890));

    let mut req = request(dir.path(), "vpn");
    req.user_override.mixed_port = Some(8080);
    assert_eq!(build_json(&req)["mixed-port"], json!(8080));
}

#[test]
fn wifi_runtime_mode_overrides_user_mode() {
    let dir = TempDir::new();
    let mut req = request(dir.path(), "vpn");
    req.user_override.mode = Some("global".to_string());
    req.wifi_runtime_mode = Some("direct".to_string());
    assert_eq!(build_json(&req)["mode"], json!("direct"));

    req.wifi_runtime_mode = Some("bogus".to_string());
    assert_eq!(build_json(&req)["mode"], json!("global"));
}

#[test]
fn selected_package_modes_match_kotlin() {
    let dir = TempDir::new();

    let mut req = request(dir.path(), "root_tun");
    req.app.app_proxy_mode = "AllowSelected".to_string();
    req.app.app_proxy_packages = vec!["com.stelliberty.android".to_string()];
    let merged = build_json(&req);
    assert_eq!(merged["tun"]["include-package"], json!(["-"]));
    assert!(merged["tun"].get("exclude-package").is_none());

    req.app.app_proxy_packages = vec![
        "com.stelliberty.android".to_string(),
        "com.example.a".to_string(),
        "com.example.a".to_string(),
    ];
    let merged = build_json(&req);
    assert_eq!(
        merged["tun"]["include-package"],
        json!(["com.example.a", "com.example.a"])
    );

    let mut req = request(dir.path(), "root_tun");
    req.app.app_proxy_mode = "DenySelected".to_string();
    req.app.app_proxy_packages = vec!["com.example.a".to_string(), "com.example.a".to_string()];
    let merged = build_json(&req);
    assert_eq!(
        merged["tun"]["exclude-package"],
        json!(["com.example.a", "com.stelliberty.android"])
    );
}

#[test]
fn invalid_mode_and_relative_path_are_rejected() {
    let dir = TempDir::new();
    let mut req = request(dir.path(), "wireguard");
    assert_eq!(build(&req).unwrap_err().code, "invalid_argument");

    req.tun_mode = "vpn".to_string();
    req.work_dir = "relative/mihomo".to_string();
    assert_eq!(build(&req).unwrap_err().code, "invalid_argument");
}

#[test]
fn summary_redacts_package_lists() {
    let dir = TempDir::new();
    let mut req = request(dir.path(), "root_tun");
    req.app.app_proxy_mode = "DenySelected".to_string();
    req.app.app_proxy_packages = vec!["com.example.a".to_string(), "com.example.b".to_string()];
    let outcome = build(&req).expect("build runtime override");

    let summary: Value = serde_json::from_str(&outcome.summary).expect("summary is JSON");
    assert!(summary["tun"].get("include-package").is_none());
    assert!(summary["tun"].get("exclude-package").is_none());
    assert_eq!(outcome.exclude_packages, 3);

    let raw: Value =
        serde_json::from_str(&fs::read_to_string(&outcome.path).expect("read override.run.json"))
            .expect("override is JSON");
    assert_eq!(raw["tun"]["exclude-package"][0], json!("com.example.a"));
}

use serde::{Deserialize, Serialize};

/// `override.run.json` 的契约：键名为 mihomo 的 kebab-case，等价于 Kotlin 的 `ConfigurationOverride`。
/// 合并结果写盘时省略 null 字段，与 Kotlin `Json(explicitNulls = false, encodeDefaults = false)` 一致。
#[derive(Debug, Clone, Default, PartialEq, Deserialize, Serialize)]
#[serde(default)]
pub struct Override {
    #[serde(rename = "port", skip_serializing_if = "Option::is_none")]
    pub http_port: Option<i32>,
    #[serde(rename = "socks-port", skip_serializing_if = "Option::is_none")]
    pub socks_port: Option<i32>,
    #[serde(rename = "redir-port", skip_serializing_if = "Option::is_none")]
    pub redir_port: Option<i32>,
    #[serde(rename = "tproxy-port", skip_serializing_if = "Option::is_none")]
    pub tproxy_port: Option<i32>,
    #[serde(rename = "mixed-port", skip_serializing_if = "Option::is_none")]
    pub mixed_port: Option<i32>,
    #[serde(rename = "routing-mark", skip_serializing_if = "Option::is_none")]
    pub routing_mark: Option<i32>,
    #[serde(rename = "allow-lan", skip_serializing_if = "Option::is_none")]
    pub allow_lan: Option<bool>,
    #[serde(rename = "ipv6", skip_serializing_if = "Option::is_none")]
    pub ipv6: Option<bool>,
    #[serde(rename = "bind-address", skip_serializing_if = "Option::is_none")]
    pub bind_address: Option<String>,
    #[serde(rename = "log-level", skip_serializing_if = "Option::is_none")]
    pub log_level: Option<String>,
    #[serde(rename = "mode", skip_serializing_if = "Option::is_none")]
    pub mode: Option<String>,
    #[serde(
        rename = "external-controller",
        skip_serializing_if = "Option::is_none"
    )]
    pub external_controller: Option<String>,
    #[serde(rename = "secret", skip_serializing_if = "Option::is_none")]
    pub secret: Option<String>,
    #[serde(rename = "unified-delay", skip_serializing_if = "Option::is_none")]
    pub unified_delay: Option<bool>,
    #[serde(rename = "geodata-mode", skip_serializing_if = "Option::is_none")]
    pub geodata_mode: Option<bool>,
    #[serde(rename = "tcp-concurrent", skip_serializing_if = "Option::is_none")]
    pub tcp_concurrent: Option<bool>,
    #[serde(rename = "find-process-mode", skip_serializing_if = "Option::is_none")]
    pub find_process_mode: Option<String>,
    #[serde(rename = "dns", skip_serializing_if = "Option::is_none")]
    pub dns: Option<Dns>,
    #[serde(rename = "sniffer", skip_serializing_if = "Option::is_none")]
    pub sniffer: Option<Sniffer>,
    #[serde(rename = "tun", skip_serializing_if = "Option::is_none")]
    pub tun: Option<Tun>,
    #[serde(rename = "profile", skip_serializing_if = "Option::is_none")]
    pub profile: Option<Profile>,
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize, Serialize)]
#[serde(default)]
pub struct Dns {
    #[serde(rename = "enable", skip_serializing_if = "Option::is_none")]
    pub enable: Option<bool>,
    #[serde(rename = "listen", skip_serializing_if = "Option::is_none")]
    pub listen: Option<String>,
    #[serde(rename = "ipv6", skip_serializing_if = "Option::is_none")]
    pub ipv6: Option<bool>,
    #[serde(rename = "prefer-h3", skip_serializing_if = "Option::is_none")]
    pub prefer_h3: Option<bool>,
    #[serde(rename = "use-hosts", skip_serializing_if = "Option::is_none")]
    pub use_hosts: Option<bool>,
    #[serde(rename = "enhanced-mode", skip_serializing_if = "Option::is_none")]
    pub enhanced_mode: Option<String>,
    #[serde(rename = "nameserver", skip_serializing_if = "Option::is_none")]
    pub nameserver: Option<Vec<String>>,
    #[serde(rename = "fallback", skip_serializing_if = "Option::is_none")]
    pub fallback: Option<Vec<String>>,
    #[serde(rename = "default-nameserver", skip_serializing_if = "Option::is_none")]
    pub default_nameserver: Option<Vec<String>>,
    #[serde(rename = "fake-ip-filter", skip_serializing_if = "Option::is_none")]
    pub fake_ip_filter: Option<Vec<String>>,
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize, Serialize)]
#[serde(default)]
pub struct Sniffer {
    #[serde(rename = "enable", skip_serializing_if = "Option::is_none")]
    pub enable: Option<bool>,
    #[serde(rename = "force-dns-mapping", skip_serializing_if = "Option::is_none")]
    pub force_dns_mapping: Option<bool>,
    #[serde(rename = "parse-pure-ip", skip_serializing_if = "Option::is_none")]
    pub parse_pure_ip: Option<bool>,
    #[serde(
        rename = "override-destination",
        skip_serializing_if = "Option::is_none"
    )]
    pub override_destination: Option<bool>,
    #[serde(rename = "force-domain", skip_serializing_if = "Option::is_none")]
    pub force_domain: Option<Vec<String>>,
    #[serde(rename = "skip-domain", skip_serializing_if = "Option::is_none")]
    pub skip_domain: Option<Vec<String>>,
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize, Serialize)]
#[serde(default)]
pub struct Tun {
    #[serde(rename = "enable", skip_serializing_if = "Option::is_none")]
    pub enable: Option<bool>,
    #[serde(rename = "device", skip_serializing_if = "Option::is_none")]
    pub device: Option<String>,
    #[serde(rename = "stack", skip_serializing_if = "Option::is_none")]
    pub stack: Option<String>,
    #[serde(rename = "file-descriptor", skip_serializing_if = "Option::is_none")]
    pub file_descriptor: Option<i32>,
    #[serde(rename = "auto-route", skip_serializing_if = "Option::is_none")]
    pub auto_route: Option<bool>,
    #[serde(
        rename = "auto-detect-interface",
        skip_serializing_if = "Option::is_none"
    )]
    pub auto_detect_interface: Option<bool>,
    #[serde(
        rename = "route-exclude-address",
        skip_serializing_if = "Option::is_none"
    )]
    pub route_exclude_address: Option<Vec<String>>,
    #[serde(rename = "inet6-address", skip_serializing_if = "Option::is_none")]
    pub inet6_address: Option<Vec<String>>,
    #[serde(rename = "dns-hijack", skip_serializing_if = "Option::is_none")]
    pub dns_hijack: Option<Vec<String>>,
    #[serde(rename = "include-package", skip_serializing_if = "Option::is_none")]
    pub include_package: Option<Vec<String>>,
    #[serde(rename = "exclude-package", skip_serializing_if = "Option::is_none")]
    pub exclude_package: Option<Vec<String>>,
    #[serde(
        rename = "iproute2-table-index",
        skip_serializing_if = "Option::is_none"
    )]
    pub iproute2_table_index: Option<i32>,
    #[serde(
        rename = "iproute2-rule-index",
        skip_serializing_if = "Option::is_none"
    )]
    pub iproute2_rule_index: Option<i32>,
    #[serde(rename = "mtu", skip_serializing_if = "Option::is_none")]
    pub mtu: Option<i32>,
    #[serde(rename = "gso", skip_serializing_if = "Option::is_none")]
    pub gso: Option<bool>,
    #[serde(rename = "gso-max-size", skip_serializing_if = "Option::is_none")]
    pub gso_max_size: Option<i32>,
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize, Serialize)]
#[serde(default)]
pub struct Profile {
    #[serde(rename = "store-selected", skip_serializing_if = "Option::is_none")]
    pub store_selected: Option<bool>,
    #[serde(rename = "store-fake-ip", skip_serializing_if = "Option::is_none")]
    pub store_fake_ip: Option<bool>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BuildRequest {
    pub work_dir: String,
    pub tun_mode: String,
    #[serde(default)]
    pub tun_fd: i32,
    #[serde(default)]
    pub mixed_port_required: bool,
    #[serde(default)]
    pub subscription_mixed_port: Option<i32>,
    #[serde(default)]
    pub tproxy_for_tether: bool,
    #[serde(default)]
    pub wifi_runtime_mode: Option<String>,
    #[serde(default)]
    pub user_override: Override,
    pub platform: Platform,
    pub app: AppState,
}

/// 平台侧常量与系统信息由 Kotlin 传入，Rust 不复制这些 Android 语义。
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Platform {
    pub vpn_tun_mtu: i32,
    pub default_mixed_port: i32,
    pub root_tproxy_port: i32,
    pub root_tether_tproxy_port: i32,
    pub root_dns_port: i32,
    pub root_tun_table_index: i32,
    pub root_tun_rule_index: i32,
    pub intranet_routes_v4: Vec<String>,
    pub intranet_routes_v6: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppState {
    pub self_package: String,
    pub app_proxy_mode: String,
    pub app_proxy_packages: Vec<String>,
    pub allow_ipv6: bool,
    pub root_tun_device: String,
    pub root_tun_jumbo_mtu: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BuildOutcome {
    pub path: String,
    pub include_packages: usize,
    pub exclude_packages: usize,
    pub summary: String,
}

use std::path::Path;

use serde_json::Value;

use crate::error::BackendError;
use crate::fsutil;

use model::{AppState, BuildOutcome, BuildRequest, Dns, Override, Platform, Profile, Tun};

pub mod model;

#[cfg(test)]
mod tests;

const RUNTIME_FILE_NAME: &str = "override.run.json";
const VPN_INET6_ADDRESS: &str = "fdfe:dcba:9876::1/126";
const DNS_HIJACK_ADDRESS: &str = "0.0.0.0:53";
const ROOT_TUN_FALLBACK_MTU: i32 = 1500;
const ROOT_TUN_GSO_MAX_SIZE: i32 = 65535;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Mode {
    Vpn,
    RootTun,
    RootTproxy,
}

impl Mode {
    fn parse(value: &str) -> Result<Self, BackendError> {
        match value {
            "vpn" => Ok(Self::Vpn),
            "root_tun" => Ok(Self::RootTun),
            "root_tproxy" => Ok(Self::RootTproxy),
            other => Err(BackendError::invalid_argument(format!(
                "unsupported tunMode: {other}"
            ))),
        }
    }

    fn is_root_tun(self) -> bool {
        matches!(self, Self::RootTun)
    }
}

pub fn handle(payload: &str) -> Result<Value, BackendError> {
    let request: BuildRequest = serde_json::from_str(payload)
        .map_err(|error| BackendError::invalid_payload("runtime_override.build", error))?;
    let outcome = build(&request)?;
    serde_json::to_value(outcome)
        .map_err(|error| BackendError::new("internal", format!("serialize outcome: {error}")))
}

pub fn build(request: &BuildRequest) -> Result<BuildOutcome, BackendError> {
    let mode = Mode::parse(&request.tun_mode)?;

    let target_dir = Path::new(request.work_dir.trim());
    if request.work_dir.trim().is_empty() || !target_dir.is_absolute() {
        return Err(BackendError::invalid_argument(
            "workDir must be an absolute path",
        ));
    }

    let merged = merge(request, mode);
    let target = target_dir.join(RUNTIME_FILE_NAME);
    let bytes = serde_json::to_vec(&merged)
        .map_err(|error| BackendError::new("internal", format!("serialize override: {error}")))?;
    fsutil::write_atomic(&target, &bytes)
        .map_err(|error| BackendError::io("write runtime override", &target, error))?;

    let (include_packages, exclude_packages) = match merged.tun.as_ref() {
        Some(tun) => (
            tun.include_package.as_ref().map_or(0, Vec::len),
            tun.exclude_package.as_ref().map_or(0, Vec::len),
        ),
        None => (0, 0),
    };

    let summary = summarize(&merged)?;

    Ok(BuildOutcome {
        path: target.display().to_string(),
        include_packages,
        exclude_packages,
        summary,
    })
}

fn merge(request: &BuildRequest, mode: Mode) -> Override {
    let platform = &request.platform;
    let mut merged = request.user_override.clone();

    // 接口地址与口令由服务自己决定，不写进 override.run.json。
    merged.external_controller = None;
    merged.secret = None;

    if let Some(wifi_mode) = request.wifi_runtime_mode.as_deref() {
        if matches!(wifi_mode, "rule" | "global" | "direct") {
            merged.mode = Some(wifi_mode.to_string());
        }
    }

    merged.mixed_port = select_mixed_port(
        merged.mixed_port,
        request.subscription_mixed_port,
        request.mixed_port_required,
        platform,
    );
    merged.tproxy_port = select_tproxy_port(merged.tproxy_port, mode, request, platform);

    merged.tcp_concurrent = Some(merged.tcp_concurrent.unwrap_or(true));
    // 统一延迟用第二次请求计时，避免把首次拨号、DNS 与 TLS 建连算进节点延迟。
    merged.unified_delay = Some(merged.unified_delay.unwrap_or(true));
    merged.find_process_mode = Some(
        merged
            .find_process_mode
            .clone()
            .unwrap_or_else(|| "off".to_string()),
    );
    merged.dns = build_dns(mode, merged.dns, platform);
    merged.tun = Some(build_tun(mode, request, platform, &request.app));
    merged.profile = Some(Profile {
        store_selected: Some(false),
        store_fake_ip: Some(true),
    });

    merged
}

fn select_mixed_port(
    user_port: Option<i32>,
    subscription_port: Option<i32>,
    required: bool,
    platform: &Platform,
) -> Option<i32> {
    match (user_port, subscription_port, required) {
        (Some(port), _, _) => Some(port),
        // 订阅自带端口时不写，免得盖掉订阅原本的设置。
        (None, Some(_), _) => None,
        (None, None, true) => Some(platform.default_mixed_port),
        (None, None, false) => None,
    }
}

fn select_tproxy_port(
    user_port: Option<i32>,
    mode: Mode,
    request: &BuildRequest,
    platform: &Platform,
) -> Option<i32> {
    match mode {
        Mode::RootTproxy => Some(platform.root_tproxy_port),
        Mode::RootTun if request.tproxy_for_tether => Some(platform.root_tether_tproxy_port),
        Mode::RootTun | Mode::Vpn => user_port,
    }
}

fn build_dns(mode: Mode, user_dns: Option<Dns>, platform: &Platform) -> Option<Dns> {
    if mode == Mode::Vpn {
        return user_dns;
    }

    let mut dns = user_dns.unwrap_or_default();
    dns.enable = Some(true);
    dns.listen = Some(format!("0.0.0.0:{}", platform.root_dns_port));
    // netd 代查的 DNS 无法按应用区分，直连应用必须拿到可路由的真实地址。
    dns.enhanced_mode = Some("redir-host".to_string());
    Some(dns)
}

fn build_tun(mode: Mode, request: &BuildRequest, platform: &Platform, app: &AppState) -> Tun {
    if mode == Mode::RootTproxy {
        return Tun {
            enable: Some(false),
            ..Tun::default()
        };
    }

    let is_root_tun = mode.is_root_tun();
    let user_tun = request.user_override.tun.clone().unwrap_or_default();
    let (include, exclude) = if is_root_tun {
        package_filters(app)
    } else {
        (None, None)
    };

    let inet6_address = if is_root_tun {
        app.allow_ipv6.then(|| vec![VPN_INET6_ADDRESS.to_string()])
    } else {
        Some(Vec::new())
    };

    // ROOT TUN 必须显式排除内网段，否则内核库会把 0.0.0.0/0 全铺进 TUN。
    let route_exclude_address = if is_root_tun {
        user_tun.route_exclude_address.clone().or_else(|| {
            let mut routes = platform.intranet_routes_v4.clone();
            if app.allow_ipv6 {
                routes.extend(platform.intranet_routes_v6.clone());
            }
            Some(routes)
        })
    } else {
        user_tun.route_exclude_address.clone()
    };

    let device = user_tun.device.clone().or_else(|| {
        if is_root_tun {
            Some(app.root_tun_device.clone())
        } else {
            None
        }
    });

    // 大包聚合：ROOT TUN 默认调大 MTU 并开 GSO；VPN 的 MTU 必须与 VpnService 一致。
    let jumbo = is_root_tun && app.root_tun_jumbo_mtu;
    let default_mtu = if is_root_tun && !jumbo {
        ROOT_TUN_FALLBACK_MTU
    } else {
        platform.vpn_tun_mtu
    };

    Tun {
        enable: Some(true),
        device,
        stack: user_tun.stack,
        file_descriptor: (!is_root_tun && request.tun_fd >= 0).then_some(request.tun_fd),
        auto_route: Some(is_root_tun),
        auto_detect_interface: Some(is_root_tun),
        route_exclude_address,
        inet6_address,
        dns_hijack: Some(vec![DNS_HIJACK_ADDRESS.to_string()]),
        include_package: include,
        exclude_package: exclude,
        iproute2_table_index: is_root_tun.then_some(platform.root_tun_table_index),
        iproute2_rule_index: is_root_tun.then_some(platform.root_tun_rule_index),
        mtu: user_tun.mtu.or(Some(default_mtu)),
        gso: user_tun
            .gso
            .or(if is_root_tun { Some(jumbo) } else { None }),
        gso_max_size: user_tun.gso_max_size.or(if is_root_tun && jumbo {
            Some(ROOT_TUN_GSO_MAX_SIZE)
        } else {
            None
        }),
    }
}

fn package_filters(app: &AppState) -> (Option<Vec<String>>, Option<Vec<String>>) {
    match app.app_proxy_mode.as_str() {
        "AllowSelected" => {
            let include: Vec<String> = app
                .app_proxy_packages
                .iter()
                .filter(|package| package.as_str() != app.self_package)
                .cloned()
                .collect();
            let include = if include.is_empty() {
                // "-" 是内核约定的「空名单」，不能写成空数组。
                vec!["-".to_string()]
            } else {
                include
            };
            (Some(include), None)
        }
        "DenySelected" => {
            let mut exclude: Vec<String> = Vec::new();
            for package in &app.app_proxy_packages {
                if !exclude.iter().any(|existing| existing == package) {
                    exclude.push(package.clone());
                }
            }
            if !exclude.iter().any(|package| package == &app.self_package) {
                exclude.push(app.self_package.clone());
            }
            (None, Some(exclude))
        }
        // 未知值按全部代理走，与 AppProxyMode.parse 的兜底一致。
        _ => (None, Some(vec![app.self_package.clone()])),
    }
}

fn summarize(merged: &Override) -> Result<String, BackendError> {
    let mut summary = merged.clone();
    if let Some(tun) = summary.tun.as_mut() {
        tun.include_package = None;
        tun.exclude_package = None;
    }
    serde_json::to_string(&summary)
        .map_err(|error| BackendError::new("internal", format!("serialize summary: {error}")))
}

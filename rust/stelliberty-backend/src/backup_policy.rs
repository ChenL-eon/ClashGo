use std::collections::HashSet;

use serde::Deserialize;
use serde_json::{json, Value};

use crate::error::BackendError;

const IMPORTED_DIR: &str = "imported";
const CONFIG_FILE: &str = "config.yaml";
const SUBSCRIPTION_LIST: &str = "subscriptions/subscriptions_list.json";
const SUBSCRIPTION_PENDING: &str = "subscriptions/pending_list.json";
const SUBSCRIPTION_SELECTION: &str = "subscriptions/selection_state.json";
const PROXY_SELECTION: &str = "proxies/selection_state.json";
const OVERRIDE_LIST: &str = "overrides/overrides_list.json";
const OVERRIDE_FILE: &str = "override.user.json";

const ANDROID_FILES: [&str; 4] = [
    SUBSCRIPTION_PENDING,
    SUBSCRIPTION_SELECTION,
    PROXY_SELECTION,
    OVERRIDE_FILE,
];

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct EntriesRequest {
    entries: Vec<String>,
    #[serde(default)]
    override_extensions: Vec<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct MergeRequest {
    #[serde(default)]
    local_ids: Vec<String>,
    #[serde(default)]
    incoming_ids: Vec<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ValidateRequest {
    #[serde(default)]
    ids: Vec<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RemoteEntry {
    name: String,
    #[serde(default)]
    last_modified: Option<i64>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RemoteRequest {
    #[serde(default)]
    entries: Vec<RemoteEntry>,
    #[serde(default)]
    retention: i64,
}

/// 包内路径白名单与订阅配置映射。返回的 `paths` 与输入顺序一一对应，`null` 表示不认识的条目
/// （PC 的 dns.json 等）直接跳过；Android 专有内容只从 `android/` 下接受。
pub fn map_entries(payload: &str) -> Result<Value, BackendError> {
    let request: EntriesRequest = parse(payload, "backup map entries")?;
    let paths = request
        .entries
        .iter()
        .map(|name| map_entry(name, &request.override_extensions))
        .collect::<Vec<_>>();
    Ok(json!({ "paths": paths }))
}

/// 合并只加入本机没有的 id；非法与重复 id 静默丢弃，重复时保留包内第一次出现。
pub fn merge_ids(payload: &str) -> Result<Value, BackendError> {
    let request: MergeRequest = parse(payload, "backup merge ids")?;
    let known = request.local_ids.into_iter().collect::<HashSet<_>>();
    let mut seen = HashSet::new();
    let ids = request
        .incoming_ids
        .into_iter()
        .filter(|id| valid_id(id) && !known.contains(id) && seen.insert(id.clone()))
        .collect::<Vec<_>>();
    Ok(json!({ "ids": ids }))
}

/// 覆盖恢复前校验覆写列表：id 必须合法且不能重复。
pub fn validate_ids(payload: &str) -> Result<Value, BackendError> {
    let request: ValidateRequest = parse(payload, "backup validate ids")?;
    let mut seen = HashSet::new();
    let valid = request
        .ids
        .iter()
        .all(|id| valid_id(id) && seen.insert(id.clone()));
    Ok(json!({ "valid": valid }))
}

/// WebDAV 备份按修改时间从新到旧、同时间按文件名倒序，只保留最近 `retention` 份。
/// PROPFIND 解析与网络请求仍在 Kotlin，排序与轮换删除的名单由这里给出。
pub fn plan_remote(payload: &str) -> Result<Value, BackendError> {
    let request: RemoteRequest = parse(payload, "backup plan remote")?;
    let mut entries = request.entries;
    entries.sort_by(|a, b| {
        b.last_modified
            .cmp(&a.last_modified)
            .then_with(|| b.name.cmp(&a.name))
    });
    let retention = request.retention.max(0) as usize;
    let latest = entries.first().map(|entry| entry.name.clone());
    let delete = entries
        .iter()
        .skip(retention)
        .map(|entry| entry.name.clone())
        .collect::<Vec<_>>();
    Ok(json!({ "latest": latest, "delete": delete }))
}

fn map_entry(name: &str, override_extensions: &[String]) -> Option<String> {
    if name == SUBSCRIPTION_LIST || name == OVERRIDE_LIST {
        return Some(name.to_owned());
    }
    if !safe_relative(name) {
        return None;
    }

    if let Some(rest) = name.strip_prefix("overrides/") {
        if let Some((id, extension)) = rest.rsplit_once('.') {
            if valid_id(id) && override_extensions.iter().any(|item| item == extension) {
                return Some(name.to_owned());
            }
        }
    }

    if let Some(rest) = name.strip_prefix("subscriptions/") {
        if let Some(id) = rest.strip_suffix(".yaml") {
            if valid_id(id) {
                return Some(format!("{IMPORTED_DIR}/{id}/{CONFIG_FILE}"));
            }
        }
    }

    let path = name.strip_prefix("android/")?;
    if !safe_relative(path) {
        return None;
    }
    if ANDROID_FILES.contains(&path) || path.starts_with("pending/") {
        return Some(path.to_owned());
    }
    if let Some(rest) = path.strip_prefix("imported/") {
        let mut parts = rest.split('/');
        let id = parts.next().unwrap_or_default();
        if valid_id(id) && parts.next().unwrap_or_default() != CONFIG_FILE {
            return Some(path.to_owned());
        }
    }
    None
}

fn valid_id(value: &str) -> bool {
    !value.is_empty()
        && value
            .chars()
            .all(|ch| ch.is_ascii_alphanumeric() || ch == '-')
}

fn safe_relative(value: &str) -> bool {
    if value.is_empty() || value.starts_with('/') || value.contains('\\') {
        return false;
    }
    value
        .split('/')
        .all(|segment| !segment.is_empty() && segment != "." && segment != "..")
}

fn parse<T: serde::de::DeserializeOwned>(payload: &str, context: &str) -> Result<T, BackendError> {
    serde_json::from_str(payload).map_err(|error| BackendError::invalid_payload(context, error))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn map_entries_request(entries: Vec<&str>) -> String {
        json!({
            "entries": entries,
            "overrideExtensions": ["yaml", "js"],
        })
        .to_string()
    }

    fn paths(value: &Value) -> Vec<Value> {
        value["paths"].as_array().unwrap().clone()
    }

    #[test]
    fn maps_the_archive_layout_to_staging_paths() {
        let value = map_entries(&map_entries_request(vec![
            SUBSCRIPTION_LIST,
            OVERRIDE_LIST,
            "overrides/abc.yaml",
            "overrides/bad.id.yaml",
            "overrides/abc.exe",
            "subscriptions/abc.yaml",
            "subscriptions/bad/id.yaml",
            "android/subscriptions/pending_list.json",
            "android/proxies/selection_state.json",
            "android/imported/abc/providers/cache.yaml",
            "android/imported/abc/config.yaml",
            "android/imported/bad.id/config.yaml",
            "android/pending/abc/config.yaml",
            "android/dns.json",
            "dns.json",
            "android/../escape.json",
        ]))
        .unwrap();

        assert_eq!(
            paths(&value),
            vec![
                json!(SUBSCRIPTION_LIST),
                json!(OVERRIDE_LIST),
                json!("overrides/abc.yaml"),
                Value::Null,
                Value::Null,
                json!("imported/abc/config.yaml"),
                Value::Null,
                json!(SUBSCRIPTION_PENDING),
                json!(PROXY_SELECTION),
                json!("imported/abc/providers/cache.yaml"),
                Value::Null,
                Value::Null,
                json!("pending/abc/config.yaml"),
                Value::Null,
                Value::Null,
                Value::Null,
            ]
        );
    }

    #[test]
    fn merge_skips_known_invalid_and_duplicate_ids() {
        let value = merge_ids(
            &json!({
                "localIds": ["local"],
                "incomingIds": ["new", "local", "bad.id", "new", "other", "-ok"],
            })
            .to_string(),
        )
        .unwrap();
        assert_eq!(value["ids"], json!(["new", "other", "-ok"]));
    }

    #[test]
    fn validate_rejects_duplicates_and_invalid_ids() {
        assert_eq!(
            validate_ids(&json!({ "ids": ["a", "b"] }).to_string()).unwrap()["valid"],
            true
        );
        assert_eq!(
            validate_ids(&json!({ "ids": ["a", "a"] }).to_string()).unwrap()["valid"],
            false
        );
        assert_eq!(
            validate_ids(&json!({ "ids": ["a", "bad.id"] }).to_string()).unwrap()["valid"],
            false
        );
    }

    #[test]
    fn remote_plan_orders_newest_first_and_keeps_retention() {
        let value = plan_remote(
            &json!({
                "entries": [
                    { "name": "old.stelliberty", "lastModified": 100 },
                    { "name": "unknown.stelliberty", "lastModified": null },
                    { "name": "new.stelliberty", "lastModified": 200 },
                    { "name": "newer.stelliberty", "lastModified": 200 },
                ],
                "retention": 2,
            })
            .to_string(),
        )
        .unwrap();

        assert_eq!(value["latest"], "newer.stelliberty");
        assert_eq!(
            value["delete"],
            json!(["old.stelliberty", "unknown.stelliberty"])
        );
    }

    #[test]
    fn empty_remote_plan_has_no_latest() {
        let value = plan_remote(&json!({ "entries": [], "retention": 5 }).to_string()).unwrap();
        assert_eq!(value["latest"], Value::Null);
        assert!(value["delete"].as_array().unwrap().is_empty());
    }
}

use serde::Deserialize;
use serde_json::{json, Value};

use crate::error::BackendError;

#[derive(Clone, Copy, Default, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
enum AutoUpdateMode {
    #[default]
    Disabled,
    Startup,
    Interval,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SubscriptionSchedule {
    id: String,
    #[serde(default)]
    is_local_file: bool,
    #[serde(default)]
    auto_update_mode: AutoUpdateMode,
    #[serde(default)]
    auto_update_interval_minutes: i64,
    created_at: i64,
    #[serde(default)]
    last_updated_at: Option<i64>,
    #[serde(default)]
    last_error_at: Option<i64>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct PlanRequest {
    now: i64,
    min_interval_minutes: i64,
    #[serde(default)]
    subscriptions: Vec<SubscriptionSchedule>,
}

/// 自动更新只由「最近一次成功或失败」决定下一次触发点，失败后也顺延一整个间隔，不立刻重试。
/// 本地文件、启动时更新与低于下限的间隔根本不进入闹钟集合，由 Rust 统一判断。
pub fn plan(payload: &str) -> Result<Value, BackendError> {
    let request: PlanRequest = parse(payload)?;
    let min_interval_ms = request.min_interval_minutes.saturating_mul(MINUTE).max(1);

    let items = request
        .subscriptions
        .iter()
        .filter_map(|subscription| {
            let interval_ms = eligible_interval(subscription, min_interval_ms)?;
            let last_attempt = last_attempt(subscription);
            let due_at = last_attempt.saturating_add(interval_ms).max(request.now);
            Some(json!({
                "id": subscription.id,
                "dueAtMillis": due_at,
                "due": request.now >= last_attempt.saturating_add(interval_ms),
            }))
        })
        .collect::<Vec<_>>();

    Ok(json!({ "items": items }))
}

const MINUTE: i64 = 60_000;

fn eligible_interval(subscription: &SubscriptionSchedule, min_interval_ms: i64) -> Option<i64> {
    if subscription.is_local_file || subscription.auto_update_mode != AutoUpdateMode::Interval {
        return None;
    }
    let interval_ms = subscription
        .auto_update_interval_minutes
        .saturating_mul(MINUTE);
    (interval_ms >= min_interval_ms).then_some(interval_ms)
}

fn last_attempt(subscription: &SubscriptionSchedule) -> i64 {
    let updated = subscription
        .last_updated_at
        .unwrap_or(subscription.created_at);
    subscription
        .last_error_at
        .map_or(updated, |error_at| updated.max(error_at))
}

fn parse<T: serde::de::DeserializeOwned>(payload: &str) -> Result<T, BackendError> {
    serde_json::from_str(payload)
        .map_err(|error| BackendError::invalid_payload("update plan", error))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn plan_request(now: i64, subscriptions: Value) -> String {
        json!({
            "now": now,
            "minIntervalMinutes": 15,
            "subscriptions": subscriptions,
        })
        .to_string()
    }

    fn subscription(
        mode: &str,
        created_at: i64,
        last_updated_at: Value,
        last_error_at: Value,
    ) -> Value {
        json!({
            "id": "s1",
            "isLocalFile": false,
            "autoUpdateMode": mode,
            "autoUpdateIntervalMinutes": 60,
            "createdAt": created_at,
            "lastUpdatedAt": last_updated_at,
            "lastErrorAt": last_error_at,
        })
    }

    fn planned_items(value: &Value) -> Vec<Value> {
        value["items"].as_array().unwrap().clone()
    }

    #[test]
    fn skips_ineligible_modes_and_short_intervals() {
        let disabled = subscription("disabled", 0, Value::Null, Value::Null);
        let startup = subscription("startup", 0, Value::Null, Value::Null);
        let local = json!({
            "id": "local",
            "isLocalFile": true,
            "autoUpdateMode": "interval",
            "autoUpdateIntervalMinutes": 60,
            "createdAt": 0,
            "lastUpdatedAt": null,
            "lastErrorAt": null,
        });
        let short = json!({
            "id": "short",
            "isLocalFile": false,
            "autoUpdateMode": "interval",
            "autoUpdateIntervalMinutes": 14,
            "createdAt": 0,
            "lastUpdatedAt": null,
            "lastErrorAt": null,
        });

        let value = plan(&plan_request(0, json!([disabled, startup, local, short]))).unwrap();
        assert!(planned_items(&value).is_empty());
    }

    #[test]
    fn schedules_from_creation_when_never_attempted() {
        let value = plan(&plan_request(
            1_000,
            json!([subscription("interval", 1_000, Value::Null, Value::Null)]),
        ))
        .unwrap();
        let items = planned_items(&value);
        assert_eq!(items.len(), 1);
        assert_eq!(items[0]["dueAtMillis"], 3_601_000);
        assert_eq!(items[0]["due"], false);
    }

    #[test]
    fn uses_the_latest_of_update_and_error() {
        let value = plan(&plan_request(
            400_000,
            json!([subscription("interval", 0, json!(100_000), json!(300_000))]),
        ))
        .unwrap();
        let items = planned_items(&value);
        assert_eq!(items[0]["dueAtMillis"], 3_900_000);
        assert_eq!(items[0]["due"], false);

        let other = plan(&plan_request(
            400_000,
            json!([subscription("interval", 0, json!(300_000), json!(100_000))]),
        ))
        .unwrap();
        assert_eq!(planned_items(&other)[0]["dueAtMillis"], 3_900_000);
    }

    #[test]
    fn overdue_and_clock_behind_are_clamped() {
        let overdue = plan(&plan_request(
            4_000_000,
            json!([subscription("interval", 0, json!(300_000), Value::Null)]),
        ))
        .unwrap();
        let items = planned_items(&overdue);
        assert_eq!(items[0]["dueAtMillis"], 4_000_000);
        assert_eq!(items[0]["due"], true);

        let behind = plan(&plan_request(
            0,
            json!([subscription(
                "interval",
                1_000_000,
                Value::Null,
                Value::Null
            )]),
        ))
        .unwrap();
        let items = planned_items(&behind);
        assert_eq!(items[0]["dueAtMillis"], 4_600_000);
        assert_eq!(items[0]["due"], false);
    }
}

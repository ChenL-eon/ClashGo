use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;

use serde::Deserialize;
use serde_json::{json, Value};

use crate::error::BackendError;
use crate::profile_fs::{commit_processing_dir, prepare_processing_dir, read_imported_text, Retry};

const MIN_AUTO_UPDATE_INTERVAL_MINUTES: i32 = 15;
const CONFIG_FILE: &str = "config.yaml";

static PIPELINE: Mutex<Option<Pipeline>> = Mutex::new(None);
static TOKEN_SEQ: AtomicU64 = AtomicU64::new(1);

struct Pipeline {
    token: String,
    uuid: String,
    kind: Kind,
    work_dir: PathBuf,
}

#[derive(Clone, Copy, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
enum Kind {
    Import,
    Update,
}

#[derive(Clone, Copy, Default, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
enum AutoUpdateMode {
    #[default]
    Disabled,
    Startup,
    Interval,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct SubscriptionFields {
    #[serde(default)]
    name: String,
    #[serde(default)]
    is_local_file: bool,
    #[serde(default)]
    source_location: String,
    #[serde(default)]
    auto_update_mode: AutoUpdateMode,
    #[serde(default)]
    auto_update_interval_minutes: i32,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ValidateRequest {
    #[serde(flatten)]
    subscription: SubscriptionFields,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct BeginRequest {
    work_dir: String,
    uuid: String,
    kind: Kind,
    #[serde(flatten)]
    subscription: SubscriptionFields,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct CommitRequest {
    token: String,
    uuid: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct AbortRequest {
    token: String,
}

pub fn validate_subscription(payload: &str) -> Result<Value, BackendError> {
    let request: ValidateRequest = parse(payload, "validate_subscription")?;
    let needs_fetch = validate_fields(&request.subscription)?;
    Ok(json!({ "needsFetch": needs_fetch }))
}

/// 校验放在提交目录之前：字段不合法时不留下 processing/ 和进行中的会话。
pub fn begin(payload: &str) -> Result<Value, BackendError> {
    let request: BeginRequest = parse(payload, "pipeline_begin")?;
    let work_dir = work_dir(&request.work_dir)?;
    let uuid = safe_uuid(&request.uuid)?;
    let needs_fetch = validate_fields(&request.subscription)?;

    let mut guard = state_lock()?;
    if guard.is_some() {
        return Err(BackendError::new(
            "pipeline_state",
            "another profile pipeline is already active",
        ));
    }

    let processing = prepare_processing_dir(&work_dir, uuid)?;
    if request.kind == Kind::Update {
        // 与旧实现一致：update 以 imported 的 config.yaml 为底，pending 里的 provider 缓存仍然沿用。
        if let Some(content) = read_imported_text(&work_dir, uuid, CONFIG_FILE)? {
            let target = processing.join(CONFIG_FILE);
            if let Err(error) = fs::write(&target, content.as_bytes()) {
                let _ = fs::remove_dir_all(&processing);
                return Err(BackendError::io("prepare update config", &target, error));
            }
        }
    }

    let token = format!(
        "pipeline-{}-{}",
        TOKEN_SEQ.fetch_add(1, Ordering::Relaxed),
        uuid
    );
    *guard = Some(Pipeline {
        token: token.clone(),
        uuid: uuid.to_owned(),
        kind: request.kind,
        work_dir,
    });

    Ok(json!({
        "token": token,
        "workDir": processing.display().to_string(),
        "needsFetch": needs_fetch,
    }))
}

pub fn commit(payload: &str) -> Result<Value, BackendError> {
    let request: CommitRequest = parse(payload, "pipeline_commit")?;
    let uuid = safe_uuid(&request.uuid)?;

    let mut guard = state_lock()?;
    let (work_dir, kind) = {
        let pipeline = guard
            .as_ref()
            .ok_or_else(|| BackendError::new("pipeline_state", "profile pipeline is not active"))?;
        if pipeline.token != request.token {
            return Err(BackendError::new(
                "pipeline_state",
                "profile pipeline token does not match",
            ));
        }
        if pipeline.uuid != uuid {
            return Err(BackendError::new(
                "pipeline_state",
                "profile pipeline uuid does not match",
            ));
        }
        (pipeline.work_dir.clone(), pipeline.kind)
    };

    let retry = commit_processing_dir(&work_dir, uuid)?;
    // 权限不足时目录还没换入，保留 token 让 Kotlin 提权后重放同一个提交。
    if retry.root_required.is_empty() {
        *guard = None;
    }
    Ok(result_value(retry, kind))
}

pub fn abort(payload: &str) -> Result<Value, BackendError> {
    let request: AbortRequest = parse(payload, "pipeline_abort")?;
    let mut guard = state_lock()?;
    match guard.as_ref() {
        Some(pipeline) if pipeline.token == request.token => {
            *guard = None;
            Ok(json!({}))
        }
        // 提交成功后 catch 仍可能走到 abort：此时没有会话，按幂等成功处理。
        None => Ok(json!({})),
        Some(_) => Err(BackendError::new(
            "pipeline_state",
            "profile pipeline token does not match",
        )),
    }
}

fn result_value(retry: Retry, kind: Kind) -> Value {
    json!({
        "rootRequired": retry.root_required,
        "cleanupPaths": retry.cleanup_paths,
        "kind": match kind {
            Kind::Import => "import",
            Kind::Update => "update",
        },
    })
}

fn validate_fields(fields: &SubscriptionFields) -> Result<bool, BackendError> {
    if fields.name.trim().is_empty() && fields.is_local_file {
        return Err(validation_error("invalid_name"));
    }
    if !fields.is_local_file {
        let source = fields.source_location.to_lowercase();
        if !source.starts_with("http://") && !source.starts_with("https://") {
            return Err(validation_error("invalid_scheme"));
        }
    }
    if fields.auto_update_mode == AutoUpdateMode::Interval
        && fields.auto_update_interval_minutes < MIN_AUTO_UPDATE_INTERVAL_MINUTES
    {
        return Err(validation_error("interval_too_small"));
    }
    Ok(!fields.is_local_file && !fields.source_location.trim().is_empty())
}

fn validation_error(kind: &'static str) -> BackendError {
    BackendError::new("profile_validation", "subscription field validation failed")
        .with_detail(kind)
}

fn state_lock() -> Result<std::sync::MutexGuard<'static, Option<Pipeline>>, BackendError> {
    PIPELINE
        .lock()
        .map_err(|_| BackendError::new("internal", "profile pipeline lock poisoned"))
}

fn parse<T: serde::de::DeserializeOwned>(payload: &str, context: &str) -> Result<T, BackendError> {
    serde_json::from_str(payload).map_err(|error| BackendError::invalid_payload(context, error))
}

fn work_dir(value: &str) -> Result<PathBuf, BackendError> {
    let path = Path::new(value.trim());
    if !path.is_absolute() {
        return Err(BackendError::invalid_argument(
            "workDir must be an absolute path",
        ));
    }
    fs::create_dir_all(path)
        .map_err(|error| BackendError::io("create profile workDir", path, error))?;
    Ok(path.to_path_buf())
}

fn safe_uuid(value: &str) -> Result<&str, BackendError> {
    if value.is_empty()
        || !value
            .chars()
            .all(|ch| ch.is_ascii_alphanumeric() || ch == '-' || ch == '_')
    {
        return Err(BackendError::invalid_argument(
            "profile id contains path separators or unsupported characters",
        ));
    }
    Ok(value)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU32, Ordering as AtomicOrdering};
    use std::sync::MutexGuard;

    static TEST_LOCK: Mutex<()> = Mutex::new(());
    static NEXT_ID: AtomicU32 = AtomicU32::new(0);

    struct TempDir(PathBuf);

    impl TempDir {
        fn new() -> Self {
            let id = NEXT_ID.fetch_add(1, AtomicOrdering::Relaxed);
            let path = std::env::temp_dir().join(format!(
                "stelliberty-profile-pipeline-{}-{id}",
                std::process::id()
            ));
            let _ = fs::remove_dir_all(&path);
            fs::create_dir_all(&path).unwrap();
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

    fn test_lock() -> MutexGuard<'static, ()> {
        let guard = TEST_LOCK.lock().unwrap();
        *state_lock().unwrap() = None;
        guard
    }

    fn write(path: &Path, content: &str) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, content).unwrap();
    }

    fn begin_request(work: &Path, uuid: &str, kind: &str) -> String {
        json!({
            "workDir": work.display().to_string(),
            "uuid": uuid,
            "kind": kind,
            "name": "Demo",
            "isLocalFile": false,
            "sourceLocation": "https://example.com/config.yaml",
            "autoUpdateMode": "disabled",
            "autoUpdateIntervalMinutes": 0,
        })
        .to_string()
    }

    fn validate_request(fields: Value) -> String {
        fields.to_string()
    }

    #[test]
    fn validation_keeps_existing_rules() {
        let local = validate_request(json!({
            "name": "   ",
            "isLocalFile": true,
            "sourceLocation": "",
            "autoUpdateMode": "disabled",
            "autoUpdateIntervalMinutes": 0,
        }));
        assert_eq!(
            validate_subscription(&local).unwrap_err().detail.as_deref(),
            Some("invalid_name")
        );

        let scheme = validate_request(json!({
            "name": "Demo",
            "isLocalFile": false,
            "sourceLocation": "ftp://example.com/config.yaml",
            "autoUpdateMode": "disabled",
            "autoUpdateIntervalMinutes": 0,
        }));
        assert_eq!(
            validate_subscription(&scheme)
                .unwrap_err()
                .detail
                .as_deref(),
            Some("invalid_scheme")
        );

        let interval = validate_request(json!({
            "name": "Demo",
            "isLocalFile": false,
            "sourceLocation": "https://example.com/config.yaml",
            "autoUpdateMode": "interval",
            "autoUpdateIntervalMinutes": 14,
        }));
        assert_eq!(
            validate_subscription(&interval)
                .unwrap_err()
                .detail
                .as_deref(),
            Some("interval_too_small")
        );

        let url = validate_request(json!({
            "name": "Demo",
            "isLocalFile": false,
            "sourceLocation": "HTTPS://example.com/config.yaml",
            "autoUpdateMode": "disabled",
            "autoUpdateIntervalMinutes": 0,
        }));
        assert_eq!(validate_subscription(&url).unwrap()["needsFetch"], true);
    }

    #[test]
    fn begin_copies_pending_and_commit_swaps_once() {
        let _lock = test_lock();
        let temp = TempDir::new();
        let work = temp.path();
        write(&work.join("pending/h1/config.yaml"), "pending config\n");

        let begun = begin(&begin_request(work, "h1", "import")).unwrap();
        let token = begun["token"].as_str().unwrap().to_owned();
        assert_eq!(
            begun["workDir"],
            work.join("processing").display().to_string()
        );
        assert_eq!(
            fs::read_to_string(work.join("processing/config.yaml")).unwrap(),
            "pending config\n"
        );

        assert!(begin(&begin_request(work, "h2", "import")).is_err());

        let commit = json!({ "token": token, "uuid": "h1" }).to_string();
        let value = commit_pipeline(&commit).unwrap();
        assert!(value["rootRequired"].as_array().unwrap().is_empty());
        assert_eq!(
            fs::read_to_string(work.join("imported/h1/config.yaml")).unwrap(),
            "pending config\n"
        );

        assert!(commit_pipeline(&commit).is_err());
    }

    #[test]
    fn update_overlays_imported_config_on_pending_cache() {
        let _lock = test_lock();
        let temp = TempDir::new();
        let work = temp.path();
        write(&work.join("pending/u1/config.yaml"), "pending config\n");
        write(&work.join("pending/u1/providers/cache.yaml"), "cache\n");
        write(&work.join("imported/u1/config.yaml"), "imported config\n");

        begin(&begin_request(work, "u1", "update")).unwrap();
        assert_eq!(
            fs::read_to_string(work.join("processing/config.yaml")).unwrap(),
            "imported config\n"
        );
        assert_eq!(
            fs::read_to_string(work.join("processing/providers/cache.yaml")).unwrap(),
            "cache\n"
        );
        abort(&json!({ "token": pipeline_token() }).to_string()).unwrap();
    }

    #[test]
    fn commit_rejects_uuid_and_token_mismatch() {
        let _lock = test_lock();
        let temp = TempDir::new();
        let work = temp.path();
        write(&work.join("pending/m1/config.yaml"), "config\n");
        begin(&begin_request(work, "m1", "import")).unwrap();
        let token = pipeline_token();

        assert!(commit_pipeline(&json!({ "token": token, "uuid": "other" }).to_string()).is_err());
        assert!(commit_pipeline(&json!({ "token": "wrong", "uuid": "m1" }).to_string()).is_err());
        abort(&json!({ "token": pipeline_token() }).to_string()).unwrap();
        assert!(abort(&json!({ "token": pipeline_token() }).to_string()).is_ok());
    }

    fn pipeline_token() -> String {
        state_lock()
            .unwrap()
            .as_ref()
            .map(|pipeline| pipeline.token.clone())
            .unwrap_or_default()
    }

    fn commit_pipeline(payload: &str) -> Result<Value, BackendError> {
        super::commit(payload)
    }
}

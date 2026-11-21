use std::path::{Path, PathBuf};
use std::sync::RwLock;

use serde_json::{json, Value};

use crate::error::BackendError;

struct BackendState {
    work_dir: PathBuf,
}

static STATE: RwLock<Option<BackendState>> = RwLock::new(None);

pub fn initialize(work_dir: &str) -> Result<Value, BackendError> {
    let trimmed = work_dir.trim();
    if trimmed.is_empty() {
        return Err(BackendError::invalid_argument("workDir must not be empty"));
    }

    let path = Path::new(trimmed);
    if !path.is_absolute() {
        return Err(BackendError::invalid_argument(
            "workDir must be an absolute path",
        ));
    }

    std::fs::create_dir_all(path)
        .map_err(|error| BackendError::io("create backend workDir", path, error))?;

    let mut guard = STATE
        .write()
        .map_err(|_| BackendError::new("internal", "backend state lock poisoned"))?;
    *guard = Some(BackendState {
        work_dir: path.to_path_buf(),
    });

    Ok(json!({
        "version": env!("CARGO_PKG_VERSION"),
        "arch": std::env::consts::ARCH,
        "workDir": path.display().to_string(),
    }))
}

pub fn info() -> Value {
    let work_dir = STATE.read().ok().and_then(|guard| {
        guard
            .as_ref()
            .map(|state| state.work_dir.display().to_string())
    });

    json!({
        "version": env!("CARGO_PKG_VERSION"),
        "arch": std::env::consts::ARCH,
        "initialized": work_dir.is_some(),
        "workDir": work_dir,
    })
}

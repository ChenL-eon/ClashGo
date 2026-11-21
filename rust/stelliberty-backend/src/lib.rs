mod error;
mod ffi;
mod fsutil;
mod runtime_override;
mod state;

pub use error::BackendError;

/// 方法名即路由：新增能力只加一个 match 分支，不新增 JNI 符号。
pub fn dispatch(method: &str, payload: &str) -> Result<serde_json::Value, BackendError> {
    match method {
        "backend.info" => Ok(state::info()),
        "runtime_override.build" => runtime_override::handle(payload),
        other => Err(BackendError::new(
            "unknown_method",
            format!("unknown backend method: {other}"),
        )),
    }
}

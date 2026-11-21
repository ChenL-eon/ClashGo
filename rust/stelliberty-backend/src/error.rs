use std::io;
use std::path::Path;

use serde_json::{json, Value};

/// 稳定的错误码：Kotlin 侧按 code 归类处理，message 只放英文技术描述。
#[derive(Debug, Clone)]
pub struct BackendError {
    pub code: &'static str,
    pub message: String,
    pub detail: Option<String>,
}

impl BackendError {
    pub fn new(code: &'static str, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
            detail: None,
        }
    }

    pub fn with_detail(mut self, detail: impl Into<String>) -> Self {
        self.detail = Some(detail.into());
        self
    }

    pub fn invalid_payload(context: &str, error: impl std::fmt::Display) -> Self {
        Self::new(
            "invalid_payload",
            format!("{context}: request payload does not match the schema"),
        )
        .with_detail(error.to_string())
    }

    pub fn invalid_argument(message: impl Into<String>) -> Self {
        Self::new("invalid_argument", message)
    }

    pub fn io(context: &str, path: &Path, error: io::Error) -> Self {
        Self::new("io", format!("{context}: {error}"))
            .with_detail(format!("path={}", path.display()))
    }

    pub fn envelope(&self) -> Value {
        json!({
            "ok": false,
            "error": {
                "code": self.code,
                "message": self.message,
                "detail": self.detail,
            }
        })
    }
}

pub fn success_envelope(data: Value) -> Value {
    json!({ "ok": true, "data": data })
}

use std::any::Any;
use std::panic::{catch_unwind, AssertUnwindSafe};

use jni::objects::{JClass, JString};
use jni::sys::jstring;
use jni::JNIEnv;

use crate::error::{success_envelope, BackendError};
use crate::{dispatch, state};

fn jstring_to_string(env: &mut JNIEnv, value: &JString) -> Result<String, BackendError> {
    let text: String = env
        .get_string(value)
        .map_err(|error| BackendError::new("jni", format!("read Java string: {error}")))?
        .into();
    Ok(text)
}

fn describe_panic(payload: Box<dyn Any + Send>) -> String {
    if let Some(text) = payload.downcast_ref::<&str>() {
        text.to_string()
    } else if let Some(text) = payload.downcast_ref::<String>() {
        text.clone()
    } else {
        "non-string panic payload".to_string()
    }
}

fn panic_error(payload: Box<dyn Any + Send>) -> BackendError {
    BackendError::new("panic", "native backend panicked").with_detail(describe_panic(payload))
}

fn handle_call(method: &str, payload: &str) -> String {
    let result = catch_unwind(AssertUnwindSafe(|| dispatch(method, payload)));
    match result {
        Ok(Ok(data)) => success_envelope(data).to_string(),
        Ok(Err(error)) => error.envelope().to_string(),
        Err(payload) => panic_error(payload).envelope().to_string(),
    }
}

fn respond(env: &mut JNIEnv, text: String) -> jstring {
    match env.new_string(text) {
        Ok(value) => value.into_raw(),
        // new_string 失败时 JVM 已挂起异常，返回 null 让 Kotlin 侧看到空结果。
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "system" fn Java_com_stelliberty_android_data_bridge_RustBackend_nativeInit(
    mut env: JNIEnv,
    _class: JClass,
    work_dir: JString,
) -> jstring {
    let result = catch_unwind(AssertUnwindSafe(|| {
        let path = jstring_to_string(&mut env, &work_dir)?;
        state::initialize(&path)
    }));

    let text = match result {
        Ok(Ok(data)) => success_envelope(data).to_string(),
        Ok(Err(error)) => error.envelope().to_string(),
        Err(payload) => panic_error(payload).envelope().to_string(),
    };
    respond(&mut env, text)
}

#[no_mangle]
pub extern "system" fn Java_com_stelliberty_android_data_bridge_RustBackend_nativeCall(
    mut env: JNIEnv,
    _class: JClass,
    method: JString,
    payload: JString,
) -> jstring {
    let result = catch_unwind(AssertUnwindSafe(|| {
        let method = jstring_to_string(&mut env, &method)?;
        let payload = jstring_to_string(&mut env, &payload)?;
        Ok::<String, BackendError>(handle_call(&method, &payload))
    }));

    let text = match result {
        Ok(Ok(text)) => text,
        Ok(Err(error)) => error.envelope().to_string(),
        Err(payload) => panic_error(payload).envelope().to_string(),
    };
    respond(&mut env, text)
}

mod backup_policy;
mod error;
mod ffi;
mod fsutil;
mod profile_fs;
mod profile_pipeline;
mod runtime_override;
mod state;
mod update_schedule;

pub use error::BackendError;

/// 方法名即路由：新增能力只加一个 match 分支，不新增 JNI 符号。
pub fn dispatch(method: &str, payload: &str) -> Result<serde_json::Value, BackendError> {
    match method {
        "backend.info" => Ok(state::info()),
        "runtime_override.build" => runtime_override::handle(payload),
        "profile.prepare_processing" => profile_fs::prepare_processing(payload),
        "profile.cleanup_processing" => profile_fs::cleanup_processing(payload),
        "profile.commit_processing" => profile_fs::commit_processing(payload),
        "profile.delete_profile_dirs" => profile_fs::delete_profile_dirs(payload),
        "profile.delete_orphan_dirs" => profile_fs::delete_orphan_dirs(payload),
        "profile.read_imported_file" => profile_fs::read_imported_file(payload),
        "profile.write_imported_file" => profile_fs::write_imported_file(payload),
        "profile.list_imported_files" => profile_fs::list_imported_files(payload),
        "profile.validate_subscription" => profile_pipeline::validate_subscription(payload),
        "profile.pipeline_begin" => profile_pipeline::begin(payload),
        "profile.pipeline_commit" => profile_pipeline::commit(payload),
        "profile.pipeline_abort" => profile_pipeline::abort(payload),
        "update.plan" => update_schedule::plan(payload),
        "backup.map_entries" => backup_policy::map_entries(payload),
        "backup.merge_ids" => backup_policy::merge_ids(payload),
        "backup.validate_ids" => backup_policy::validate_ids(payload),
        "backup.plan_remote" => backup_policy::plan_remote(payload),
        other => Err(BackendError::new(
            "unknown_method",
            format!("unknown backend method: {other}"),
        )),
    }
}

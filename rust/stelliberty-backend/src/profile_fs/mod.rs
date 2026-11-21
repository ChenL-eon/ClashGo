use std::collections::HashSet;
use std::fs;
use std::io;
use std::path::{Component, Path, PathBuf};

use serde::Deserialize;
use serde_json::{json, Value};

use crate::error::BackendError;

const IMPORTS: &str = "imported";
const PENDING: &str = "pending";
const RUNTIME: &str = "runtime";
const PROCESSING: &str = "processing";
const STAGING: &str = "commit.new";
const OLD_PREFIX: &str = "commit.old.";

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkDirRequest {
    work_dir: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct UuidRequest {
    work_dir: String,
    uuid: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct OrphansRequest {
    work_dir: String,
    known_uuids: Vec<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct FileRequest {
    work_dir: String,
    uuid: String,
    relative_path: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct WriteFileRequest {
    work_dir: String,
    uuid: String,
    relative_path: String,
    content: String,
}

/// 目录操作遇到 EACCES 时不在这里提权：把路径交给 Kotlin 的 su 兜底，
/// 清完再重放同一个请求。其它 IO 错误直接失败，避免把真实故障当成权限问题重试。
struct Retry {
    root_required: Vec<String>,
    cleanup_paths: Vec<String>,
}

impl Retry {
    fn new() -> Self {
        Self {
            root_required: Vec::new(),
            cleanup_paths: Vec::new(),
        }
    }

    fn into_value(self) -> Value {
        json!({
            "rootRequired": self.root_required,
            "cleanupPaths": self.cleanup_paths,
        })
    }
}

pub fn prepare_processing(payload: &str) -> Result<Value, BackendError> {
    let request: UuidRequest = parse(payload, "prepare_processing")?;
    let work_dir = work_dir(&request.work_dir)?;
    let uuid = safe_uuid(&request.uuid)?;

    let processing = work_dir.join(PROCESSING);
    remove_dir_all(&processing, "reset processing")?;
    fs::create_dir_all(&processing)
        .map_err(|error| BackendError::io("create processing", &processing, error))?;

    let pending = work_dir.join(PENDING).join(uuid);
    if pending.exists() {
        copy_dir_contents(&pending, &processing)?;
    }

    Ok(json!({ "path": processing.display().to_string() }))
}

pub fn cleanup_processing(payload: &str) -> Result<Value, BackendError> {
    let request: WorkDirRequest = parse(payload, "cleanup_processing")?;
    let work_dir = work_dir(&request.work_dir)?;
    let mut retry = Retry::new();

    for path in [work_dir.join(PROCESSING), work_dir.join(STAGING)] {
        remove_dir_lenient(&path, &mut retry.root_required);
    }

    let imports = work_dir.join(IMPORTS);
    if let Ok(entries) = fs::read_dir(&work_dir) {
        for entry in entries.flatten() {
            if !entry.path().is_dir() {
                continue;
            }
            let name = entry.file_name();
            let Some(name) = name.to_str() else { continue };
            let Some(uuid) = name.strip_prefix(OLD_PREFIX) else {
                continue;
            };
            if uuid.is_empty() {
                continue;
            }
            let old = entry.path();
            let imported = imports.join(uuid);
            if imported.exists() {
                remove_dir_lenient(&old, &mut retry.root_required);
            } else if let Some(parent) = imported.parent() {
                fs::create_dir_all(parent).map_err(|error| {
                    BackendError::io("create imported parent while restoring", parent, error)
                })?;
                // 改名失败不丢数据：旧目录还在，下次启动会再试一次。
                let _ = fs::rename(&old, &imported);
            }
        }
    }

    Ok(retry.into_value())
}

pub fn commit_processing(payload: &str) -> Result<Value, BackendError> {
    let request: UuidRequest = parse(payload, "commit_processing")?;
    let work_dir = work_dir(&request.work_dir)?;
    let uuid = safe_uuid(&request.uuid)?;

    let processing = work_dir.join(PROCESSING);
    let imported = work_dir.join(IMPORTS).join(uuid);
    let pending = work_dir.join(PENDING).join(uuid);
    let staging = work_dir.join(STAGING);
    let old = work_dir.join(format!("{OLD_PREFIX}{uuid}"));
    let mut retry = Retry::new();

    if !remove_dir_blocking(&staging, &mut retry.root_required)? {
        return Ok(retry.into_value());
    }
    if !remove_dir_blocking(&old, &mut retry.root_required)? {
        return Ok(retry.into_value());
    }

    fs::create_dir_all(&staging)
        .map_err(|error| BackendError::io("create commit staging", &staging, error))?;
    let copy_result = if processing.exists() {
        copy_dir_contents(&processing, &staging)
    } else {
        Ok(())
    };
    if let Err(error) = copy_result {
        let _ = fs::remove_dir_all(&staging);
        return Err(error);
    }

    if let Some(parent) = imported.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| BackendError::io("create imported parent", parent, error))?;
    }

    // imported/ 一律先拷后 rename：删除全部排在拷贝之后，失败时原目录仍然完整。
    let moved_aside = imported.exists();
    if moved_aside {
        if let Err(error) = fs::rename(&imported, &old) {
            let _ = fs::remove_dir_all(&staging);
            return Err(BackendError::io("move imported aside", &imported, error));
        }
    }

    if let Err(error) = fs::rename(&staging, &imported) {
        if moved_aside {
            let _ = fs::rename(&old, &imported);
        }
        let _ = fs::remove_dir_all(&staging);
        return Err(BackendError::io("swap in imported", &imported, error));
    }

    if moved_aside {
        // 已换入新目录，旧目录删不掉不能再让整个提交失败；交给 Kotlin 提权后尽力清理。
        remove_dir_lenient(&old, &mut retry.cleanup_paths);
    }
    if pending.exists() {
        let _ = fs::remove_dir_all(&pending);
    }

    Ok(retry.into_value())
}

pub fn delete_profile_dirs(payload: &str) -> Result<Value, BackendError> {
    let request: UuidRequest = parse(payload, "delete_profile_dirs")?;
    let work_dir = work_dir(&request.work_dir)?;
    let uuid = safe_uuid(&request.uuid)?;
    let mut retry = Retry::new();

    delete_dirs(&work_dir, uuid, &mut retry.root_required)?;
    Ok(retry.into_value())
}

pub fn delete_orphan_dirs(payload: &str) -> Result<Value, BackendError> {
    let request: OrphansRequest = parse(payload, "delete_orphan_dirs")?;
    let work_dir = work_dir(&request.work_dir)?;
    let known: HashSet<&str> = request.known_uuids.iter().map(String::as_str).collect();

    let mut orphans = Vec::new();
    for sub in [IMPORTS, PENDING] {
        let directory = work_dir.join(sub);
        let entries = match fs::read_dir(&directory) {
            Ok(entries) => entries,
            Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
            Err(error) => {
                return Err(BackendError::io(
                    "scan profile directories",
                    &directory,
                    error,
                ))
            }
        };
        for entry in entries.flatten() {
            if !entry.path().is_dir() {
                continue;
            }
            let name = entry.file_name();
            let Some(name) = name.to_str() else { continue };
            if name.is_empty() || known.contains(name) {
                continue;
            }
            if !orphans.iter().any(|value: &String| value == name) {
                orphans.push(name.to_owned());
            }
        }
    }

    let mut retry = Retry::new();
    for uuid in &orphans {
        // 单个孤儿删除失败不阻塞其余目录，失败路径留给 Kotlin 提权后整轮重放。
        delete_dirs(&work_dir, uuid, &mut retry.root_required)?;
    }

    Ok(json!({
        "orphans": orphans,
        "rootRequired": retry.root_required,
        "cleanupPaths": retry.cleanup_paths,
    }))
}

pub fn read_imported_file(payload: &str) -> Result<Value, BackendError> {
    let request: FileRequest = parse(payload, "read_imported_file")?;
    let work_dir = work_dir(&request.work_dir)?;
    let uuid = safe_uuid(&request.uuid)?;
    let root = work_dir.join(IMPORTS).join(uuid);
    let relative = checked_relative(&request.relative_path)?;

    if !root.exists() {
        return Ok(json!({ "content": null }));
    }
    if !root.is_dir() {
        return Ok(json!({ "content": null }));
    }
    let canonical_root = fs::canonicalize(&root)
        .map_err(|error| BackendError::io("resolve imported directory", &root, error))?;
    let target = canonical_root.join(relative);

    let canonical_target = match fs::canonicalize(&target) {
        Ok(path) => path,
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            return Ok(json!({ "content": null }));
        }
        Err(_) => return Ok(json!({ "content": null })),
    };
    if !canonical_target.starts_with(&canonical_root) || !canonical_target.is_file() {
        return Ok(json!({ "content": null }));
    }

    // 与旧实现一致：编辑器打不开的文件按「无内容」处理，不让一条坏文件把页面协程打挂。
    let Ok(bytes) = fs::read(&canonical_target) else {
        return Ok(json!({ "content": null }));
    };
    let Ok(content) = String::from_utf8(bytes) else {
        return Ok(json!({ "content": null }));
    };
    Ok(json!({ "content": content }))
}

pub fn write_imported_file(payload: &str) -> Result<Value, BackendError> {
    let request: WriteFileRequest = parse(payload, "write_imported_file")?;
    let work_dir = work_dir(&request.work_dir)?;
    let uuid = safe_uuid(&request.uuid)?;
    let root = work_dir.join(IMPORTS).join(uuid);
    let relative = checked_relative(&request.relative_path)?;

    let requested = root.join(&relative);
    let parent = requested
        .parent()
        .ok_or_else(|| BackendError::invalid_argument("imported file path has no parent"))?;
    fs::create_dir_all(parent)
        .map_err(|error| BackendError::io("create imported parent", parent, error))?;

    let canonical_root = fs::canonicalize(&root)
        .map_err(|error| BackendError::io("resolve imported directory", &root, error))?;
    let canonical_parent = fs::canonicalize(parent)
        .map_err(|error| BackendError::io("resolve imported parent", parent, error))?;
    let file_name = requested
        .file_name()
        .ok_or_else(|| BackendError::invalid_argument("imported file path has no file name"))?;
    // 目标已存在时按真实路径写：符号链接指向订阅目录外必须拦下，否则 write 会顺着链接逃逸。
    let target = match fs::canonicalize(&requested) {
        Ok(path) => path,
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            let dangling_link = fs::symlink_metadata(&requested)
                .map(|metadata| metadata.file_type().is_symlink())
                .unwrap_or(false);
            if dangling_link {
                return Err(BackendError::invalid_argument(format!(
                    "path traversal blocked: {}",
                    request.relative_path
                )));
            }
            canonical_parent.join(file_name)
        }
        Err(error) => return Err(BackendError::io("resolve imported file", &requested, error)),
    };
    if !target.starts_with(&canonical_root) {
        return Err(BackendError::invalid_argument(format!(
            "path traversal blocked: {}",
            request.relative_path
        )));
    }

    // 保持原有语义：编辑器保存是普通覆盖写，不走订阅列表那种先写临时文件再 rename。
    fs::write(&target, request.content.as_bytes())
        .map_err(|error| BackendError::io("write imported file", &target, error))?;
    Ok(json!({}))
}

pub fn list_imported_files(payload: &str) -> Result<Value, BackendError> {
    let request: UuidRequest = parse(payload, "list_imported_files")?;
    let work_dir = work_dir(&request.work_dir)?;
    let uuid = safe_uuid(&request.uuid)?;
    let root = work_dir.join(IMPORTS).join(uuid);
    if !root.exists() {
        return Ok(json!([]));
    }
    if !root.is_dir() {
        return Ok(json!([]));
    }

    let canonical_root = fs::canonicalize(&root)
        .map_err(|error| BackendError::io("resolve imported directory", &root, error))?;
    let mut files = Vec::new();
    collect_files(&canonical_root, &canonical_root, &mut files)?;
    files.sort();
    Ok(json!(files))
}

fn delete_dirs(
    work_dir: &Path,
    uuid: &str,
    root_required: &mut Vec<String>,
) -> Result<(), BackendError> {
    for sub in [IMPORTS, PENDING, RUNTIME] {
        remove_dir_lenient(&work_dir.join(sub).join(uuid), root_required);
    }
    Ok(())
}

fn collect_files(root: &Path, current: &Path, files: &mut Vec<String>) -> Result<(), BackendError> {
    let entries = match fs::read_dir(current) {
        Ok(entries) => entries,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(BackendError::io("list imported directory", current, error)),
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let file_type = match entry.file_type() {
            Ok(file_type) => file_type,
            Err(_) => continue,
        };
        if file_type.is_dir() {
            collect_files(root, &path, files)?;
        } else if file_type.is_file() {
            push_relative(root, &path, files);
        } else if file_type.is_symlink() {
            // 只把指向文件的链接算作文件；目录链接不递归，避免跑出订阅目录。
            if fs::metadata(&path)
                .map(|meta| meta.is_file())
                .unwrap_or(false)
            {
                push_relative(root, &path, files);
            }
        }
    }
    Ok(())
}

fn push_relative(root: &Path, path: &Path, files: &mut Vec<String>) {
    if let Ok(relative) = path.strip_prefix(root) {
        let value = relative
            .components()
            .filter_map(|component| match component {
                Component::Normal(value) => Some(value.to_string_lossy().into_owned()),
                _ => None,
            })
            .collect::<Vec<_>>()
            .join("/");
        if !value.is_empty() {
            files.push(value);
        }
    }
}

fn copy_dir_contents(source: &Path, target: &Path) -> Result<(), BackendError> {
    let entries = fs::read_dir(source)
        .map_err(|error| BackendError::io("read profile source", source, error))?;
    for entry in entries {
        let entry =
            entry.map_err(|error| BackendError::io("read profile source", source, error))?;
        let source_path = entry.path();
        let target_path = target.join(entry.file_name());
        let file_type = entry
            .file_type()
            .map_err(|error| BackendError::io("inspect profile source", &source_path, error))?;

        if file_type.is_dir() {
            fs::create_dir_all(&target_path).map_err(|error| {
                BackendError::io("create profile directory", &target_path, error)
            })?;
            copy_dir_contents(&source_path, &target_path)?;
        } else if file_type.is_file() {
            copy_file(&source_path, &target_path)?;
        } else if file_type.is_symlink() {
            copy_symlink(&source_path, &target_path)?;
        }
    }
    Ok(())
}

fn copy_file(source: &Path, target: &Path) -> Result<(), BackendError> {
    fs::copy(source, target)
        .map_err(|error| BackendError::io("copy profile file", source, error))?;
    // provider 新鲜度按修改时间比较，复制不能把 mtime 变成当前时间。
    if let Ok(metadata) = fs::metadata(source) {
        if let Ok(mtime) = metadata.modified() {
            let times = fs::FileTimes::new().set_modified(mtime);
            fs::set_times(target, times)
                .map_err(|error| BackendError::io("preserve profile mtime", target, error))?;
        }
    }
    Ok(())
}

#[cfg(unix)]
fn copy_symlink(source: &Path, target: &Path) -> Result<(), BackendError> {
    use std::os::unix::fs::symlink;

    let link = fs::read_link(source)
        .map_err(|error| BackendError::io("read profile symlink", source, error))?;
    let _ = fs::remove_file(target);
    symlink(&link, target)
        .map_err(|error| BackendError::io("recreate profile symlink", target, error))
}

#[cfg(not(unix))]
fn copy_symlink(source: &Path, target: &Path) -> Result<(), BackendError> {
    // Windows 测试环境没有 Android 的 geodata 链接；按普通文件复制即可。
    match fs::metadata(source) {
        Ok(metadata) if metadata.is_file() => copy_file(source, target),
        _ => Ok(()),
    }
}

fn remove_dir_all(path: &Path, context: &str) -> Result<(), BackendError> {
    match fs::remove_dir_all(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(BackendError::io(context, path, error)),
    }
}

/// 删除成功返回 true；权限不足把路径记进 root_required 并返回 false，调用方必须停下等待提权重放。
fn remove_dir_blocking(path: &Path, root_required: &mut Vec<String>) -> Result<bool, BackendError> {
    match fs::remove_dir_all(path) {
        Ok(()) => Ok(true),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(true),
        Err(error) if error.kind() == io::ErrorKind::PermissionDenied => {
            root_required.push(path.display().to_string());
            Ok(false)
        }
        Err(error) => Err(BackendError::io("remove profile directory", path, error)),
    }
}

/// 清理类操作不因一个目录删不掉就放弃其它目录；只有可能是 root 属主的错误才回传路径。
/// 其余错误保持旧实现的尽力而为语义：目标没删掉，但调用方继续。
fn remove_dir_lenient(path: &Path, root_required: &mut Vec<String>) {
    match fs::remove_dir_all(path) {
        Ok(()) => {}
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) if error.kind() == io::ErrorKind::PermissionDenied => {
            root_required.push(path.display().to_string());
        }
        Err(_) => {}
    }
}

fn checked_relative(value: &str) -> Result<PathBuf, BackendError> {
    let path = Path::new(value);
    if value.is_empty() || path.is_absolute() {
        return Err(BackendError::invalid_argument(
            "imported file path must be relative",
        ));
    }
    for component in path.components() {
        match component {
            Component::Normal(_) => {}
            Component::CurDir => {}
            _ => {
                return Err(BackendError::invalid_argument(format!(
                    "path traversal blocked: {value}"
                )))
            }
        }
    }
    Ok(path.to_path_buf())
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
    if !is_safe_uuid(value) {
        return Err(BackendError::invalid_argument(
            "profile id contains path separators or unsupported characters",
        ));
    }
    Ok(value)
}

fn is_safe_uuid(value: &str) -> bool {
    !value.is_empty()
        && value
            .chars()
            .all(|ch| ch.is_ascii_alphanumeric() || ch == '-' || ch == '_')
}

fn parse<T: serde::de::DeserializeOwned>(payload: &str, context: &str) -> Result<T, BackendError> {
    serde_json::from_str(payload).map_err(|error| BackendError::invalid_payload(context, error))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU32, Ordering};
    use std::time::{Duration, SystemTime};

    static NEXT_ID: AtomicU32 = AtomicU32::new(0);

    struct TempDir(PathBuf);

    impl TempDir {
        fn new() -> Self {
            let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir().join(format!(
                "stelliberty-profile-fs-{}-{id}",
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

    fn work_request(work: &Path) -> String {
        json!({ "workDir": work.display().to_string() }).to_string()
    }

    fn uuid_request(work: &Path, uuid: &str) -> String {
        json!({
            "workDir": work.display().to_string(),
            "uuid": uuid,
        })
        .to_string()
    }

    fn file_request(work: &Path, uuid: &str, path: &str, content: Option<&str>) -> String {
        match content {
            Some(content) => json!({
                "workDir": work.display().to_string(),
                "uuid": uuid,
                "relativePath": path,
                "content": content,
            }),
            None => json!({
                "workDir": work.display().to_string(),
                "uuid": uuid,
                "relativePath": path,
            }),
        }
        .to_string()
    }

    fn write(path: &Path, content: &str) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, content).unwrap();
    }

    #[test]
    fn prepare_copies_pending_and_preserves_mtime() {
        let temp = TempDir::new();
        let work = temp.path();
        write(&work.join("pending/a1/config.yaml"), "proxies: []\n");
        write(&work.join("pending/a1/providers/demo.yaml"), "payload\n");
        let mtime = SystemTime::UNIX_EPOCH + Duration::from_secs(1_600_000_000);
        fs::set_times(
            work.join("pending/a1/providers/demo.yaml"),
            fs::FileTimes::new().set_modified(mtime),
        )
        .unwrap();

        let value = prepare_processing(&uuid_request(work, "a1")).unwrap();
        assert_eq!(value["path"], work.join("processing").display().to_string());
        assert_eq!(
            fs::read_to_string(work.join("processing/config.yaml")).unwrap(),
            "proxies: []\n"
        );
        assert_eq!(
            fs::metadata(work.join("processing/providers/demo.yaml"))
                .unwrap()
                .modified()
                .unwrap(),
            mtime
        );
    }

    #[test]
    fn commit_swaps_imported_and_clears_staging() {
        let temp = TempDir::new();
        let work = temp.path();
        write(&work.join("pending/b2/config.yaml"), "new config\n");
        prepare_processing(&uuid_request(work, "b2")).unwrap();

        let value = commit_processing(&uuid_request(work, "b2")).unwrap();
        assert!(value["rootRequired"].as_array().unwrap().is_empty());
        assert_eq!(
            fs::read_to_string(work.join("imported/b2/config.yaml")).unwrap(),
            "new config\n"
        );
        assert!(!work.join("pending/b2").exists());
        assert!(!work.join("commit.new").exists());
        assert!(!work.join("commit.old.b2").exists());
    }

    #[test]
    fn commit_replaces_previous_import_without_data_loss_on_copy_failure() {
        let temp = TempDir::new();
        let work = temp.path();
        write(&work.join("imported/c3/config.yaml"), "old config\n");
        write(&work.join("processing/config.yaml"), "updated config\n");

        commit_processing(&uuid_request(work, "c3")).unwrap();
        assert_eq!(
            fs::read_to_string(work.join("imported/c3/config.yaml")).unwrap(),
            "updated config\n"
        );
        assert!(!work.join("commit.old.c3").exists());
    }

    #[test]
    fn cleanup_restores_interrupted_commit() {
        let temp = TempDir::new();
        let work = temp.path();
        write(&work.join("commit.old.d4/config.yaml"), "previous config\n");

        cleanup_processing(&work_request(work)).unwrap();
        assert_eq!(
            fs::read_to_string(work.join("imported/d4/config.yaml")).unwrap(),
            "previous config\n"
        );
        assert!(!work.join("commit.old.d4").exists());
    }

    #[test]
    fn cleanup_discards_old_copy_when_import_exists() {
        let temp = TempDir::new();
        let work = temp.path();
        write(&work.join("imported/e5/config.yaml"), "current config\n");
        write(&work.join("commit.old.e5/config.yaml"), "stale config\n");
        write(&work.join("processing/config.yaml"), "partial\n");
        write(&work.join("commit.new/config.yaml"), "partial\n");

        cleanup_processing(&work_request(work)).unwrap();
        assert_eq!(
            fs::read_to_string(work.join("imported/e5/config.yaml")).unwrap(),
            "current config\n"
        );
        assert!(!work.join("commit.old.e5").exists());
        assert!(!work.join("processing").exists());
        assert!(!work.join("commit.new").exists());
    }

    #[test]
    fn orphan_scan_keeps_known_profiles_and_removes_rest() {
        let temp = TempDir::new();
        let work = temp.path();
        write(&work.join("imported/keep/config.yaml"), "keep\n");
        write(&work.join("imported/drop/config.yaml"), "drop\n");
        write(&work.join("pending/draft/config.yaml"), "draft\n");
        write(&work.join("runtime/drop/cache.bin"), "cache\n");

        let payload = json!({
            "workDir": work.display().to_string(),
            "knownUuids": ["keep"],
        })
        .to_string();
        let value = delete_orphan_dirs(&payload).unwrap();
        let orphans = value["orphans"].as_array().unwrap().clone();
        assert_eq!(orphans.len(), 2);
        assert!(work.join("imported/keep").exists());
        assert!(!work.join("imported/drop").exists());
        assert!(!work.join("pending/draft").exists());
        assert!(!work.join("runtime/drop").exists());
    }

    #[test]
    fn imported_file_access_blocks_traversal_and_roundtrips_emoji() {
        let temp = TempDir::new();
        let work = temp.path();
        let root = work.join("imported/f6");
        fs::create_dir_all(&root).unwrap();
        write(&root.join("config.yaml"), "initial\n");

        let written =
            write_imported_file(&file_request(work, "f6", "config.yaml", Some("订阅 😀\n")))
                .unwrap();
        assert_eq!(written, json!({}));

        let value = read_imported_file(&file_request(work, "f6", "config.yaml", None)).unwrap();
        assert_eq!(value["content"], "订阅 😀\n");

        for path in [
            "../outside.yaml",
            "/data/local/tmp/x",
            "providers/../../../x",
        ] {
            assert!(read_imported_file(&file_request(work, "f6", path, None)).is_err());
            assert!(write_imported_file(&file_request(work, "f6", path, Some("x"))).is_err());
        }
    }

    #[test]
    fn list_imported_files_is_sorted_and_rooted() {
        let temp = TempDir::new();
        let work = temp.path();
        write(&work.join("imported/g7/providers/b.yaml"), "b\n");
        write(&work.join("imported/g7/config.yaml"), "a\n");
        fs::create_dir_all(work.join("imported/g7/providers/nested")).unwrap();
        write(&work.join("imported/g7/providers/nested/a.yaml"), "c\n");

        let value = list_imported_files(&uuid_request(work, "g7")).unwrap();
        assert_eq!(
            value,
            json!(["config.yaml", "providers/b.yaml", "providers/nested/a.yaml"])
        );
    }

    #[test]
    fn unsafe_uuid_is_rejected() {
        let temp = TempDir::new();
        for uuid in ["../escape", "a/b", "", "a b"] {
            assert!(prepare_processing(&uuid_request(temp.path(), uuid)).is_err());
        }
    }
}

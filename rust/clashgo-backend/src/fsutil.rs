use std::fs::{self, File};
use std::io::{self, Write};
use std::path::Path;

/// 与 Android 侧 `ProfileFileOps.writeAtomically` 同一语义：同目录临时文件 → fsync → rename。
/// 目录项也刷一次盘，避免掉电后只留下空目录或旧文件。
pub fn write_atomic(path: &Path, contents: &[u8]) -> io::Result<()> {
    let parent = path.parent().ok_or_else(|| {
        io::Error::new(io::ErrorKind::InvalidInput, "path has no parent directory")
    })?;
    fs::create_dir_all(parent)?;

    let file_name = path
        .file_name()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "path has no file name"))?
        .to_string_lossy();
    let temp = parent.join(format!("{file_name}.tmp"));

    let write_result = (|| -> io::Result<()> {
        let mut file = File::create(&temp)?;
        file.write_all(contents)?;
        file.sync_all()
    })();
    if let Err(error) = write_result {
        let _ = fs::remove_file(&temp);
        return Err(error);
    }

    // Windows 的 rename 不允许覆盖已存在目标；Android/Linux 上 rename 本身即原子替换。
    #[cfg(windows)]
    if path.exists() {
        fs::remove_file(path)?;
    }

    if let Err(error) = fs::rename(&temp, path) {
        let _ = fs::remove_file(&temp);
        return Err(error);
    }

    sync_directory(parent);
    Ok(())
}

#[cfg(unix)]
fn sync_directory(path: &Path) {
    if let Ok(directory) = File::open(path) {
        let _ = directory.sync_all();
    }
}

#[cfg(not(unix))]
fn sync_directory(_path: &Path) {}

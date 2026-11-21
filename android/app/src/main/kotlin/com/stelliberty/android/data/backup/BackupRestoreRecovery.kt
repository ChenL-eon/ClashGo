package com.stelliberty.android.data.backup

import android.content.Context
import com.stelliberty.android.util.AppLogger
import java.io.File

// 覆盖恢复在两次 rename 之间被杀时会留下 .restore-old：正式目录已经移走、新的还没换入。
// 必须在 Koin 读取订阅/设置之前把旧目录放回原位，否则 JSON 存储会以空值启动，下一次恢复还会把唯一的旧副本删掉。
internal object BackupRestoreRecovery {

    private const val TAG = "BackupRestoreRecovery"

    fun recover(context: Context): Boolean {
        val root = File(context.filesDir, "mihomo")
        val old = File(root, BackupManager.RESTORE_OLD)
        val staging = File(root, BackupManager.RESTORE_STAGING)
        if (!old.exists() && !staging.exists()) return true
        if (!old.exists() && staging.exists()) {
            AppLogger.info(TAG, "Removing incomplete restore staging")
            return staging.deleteRecursively()
        }
        if (!old.isDirectory) {
            AppLogger.error(TAG, "Restore backup path is not a directory: ${old.absolutePath}")
            return false
        }

        var restoredAll = true
        BackupManager.RESTORE_TARGETS.forEach { name ->
            val saved = File(old, name)
            if (!saved.exists()) return@forEach
            val current = File(root, name)
            if (current.exists()) {
                // 新目录已经换入，旧副本只是 swap 成功后没来得及删除的残留。
                if (!saved.deleteRecursively()) {
                    restoredAll = false
                    AppLogger.warn(TAG, "Cannot remove redundant restore backup: ${saved.absolutePath}")
                }
                return@forEach
            }

            current.parentFile?.mkdirs()
            if (saved.renameTo(current)) {
                AppLogger.info(TAG, "Restored interrupted restore target: $name")
            } else {
                restoredAll = false
                AppLogger.error(TAG, "Cannot restore interrupted restore target: ${saved.absolutePath}")
            }
        }

        if (restoredAll) {
            if (old.listFiles().isNullOrEmpty()) {
                old.delete()
            } else {
                AppLogger.warn(TAG, "Restore backup has unknown leftovers: ${old.absolutePath}")
            }
            staging.deleteRecursively()
        }
        return restoredAll
    }
}

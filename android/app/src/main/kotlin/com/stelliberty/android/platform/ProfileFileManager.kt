package com.stelliberty.android.platform

import com.stelliberty.android.domain.model.Subscription

enum class ProfilePipelineKind { Import, Update }

data class ProfileProcessingSession(val token: String, val workDir: String)

interface ProfileFileManager {
    fun savePendingConfig(uuid: String, content: String)
    fun releasePending(uuid: String)

    fun beginProcessing(
        uuid: String,
        kind: ProfilePipelineKind,
        subscription: Subscription,
    ): ProfileProcessingSession

    fun commitProcessing(token: String, uuid: String)
    fun abortProcessing(token: String)

    fun cleanupProcessing()

    fun getMihomoWorkDir(): String

    fun readMihomoFile(relativePath: String): String?

    fun writeMihomoFile(relativePath: String, content: String)

    fun backupMihomoFile(relativePath: String)

    fun getImportedDir(uuid: String): String
    fun listImportedFiles(uuid: String): List<String>
    fun readImportedFile(uuid: String, relativePath: String): String?
    fun writeImportedFile(uuid: String, relativePath: String, content: String)
    fun deleteDirs(uuid: String)

    fun deleteOrphanDirs(knownUuids: Set<String>): List<String>
}

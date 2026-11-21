package com.stelliberty.android.data.backup

import com.stelliberty.android.data.bridge.RustBackend
import com.stelliberty.android.domain.model.OverrideFormat
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
private data class MapEntriesRequest(val entries: List<String>, val overrideExtensions: List<String>)

@Serializable
private data class MapEntriesResult(val paths: List<String?> = emptyList())

@Serializable
private data class MergeIdsRequest(val localIds: List<String>, val incomingIds: List<String>)

@Serializable
private data class MergeIdsResult(val ids: List<String> = emptyList())

@Serializable
private data class ValidateIdsRequest(val ids: List<String>)

@Serializable
private data class ValidateIdsResult(val valid: Boolean = false)

@Serializable
private data class RemoteEntry(val name: String, val lastModified: Long? = null)

@Serializable
private data class RemotePlanRequest(val entries: List<RemoteEntry>, val retention: Int)

@Serializable
private data class RemotePlanResult(val latest: String? = null, val delete: List<String> = emptyList())

data class RemotePlan(val latest: String?, val delete: List<String>)

// 备份包布局白名单、覆盖 id 合并与 WebDAV 轮换名单都在 Rust；Kotlin 仍负责 zip 流、
// 模型反序列化、Ktor 请求与 Android ContentResolver，Rust 不持有流或 Context。
internal object BackupPolicy {

    private val json = Json {
        encodeDefaults = true
        explicitNulls = false
        ignoreUnknownKeys = true
    }

    private val overrideExtensions = OverrideFormat.entries.map { it.extension }

    // 返回与包内条目一一对应的暂存路径；null 表示不认识的条目，直接跳过。
    fun mapEntries(entries: List<String>): List<String?> {
        val payload = json.encodeToString(
            MapEntriesRequest.serializer(),
            MapEntriesRequest(entries, overrideExtensions),
        )
        val paths = RustBackend.call(
            "backup.map_entries",
            payload,
            MapEntriesResult.serializer(),
        ).paths
        if (paths.size != entries.size) throw BackupException("Invalid backup entry plan")
        return paths
    }

    fun mergeIds(localIds: List<String>, incomingIds: List<String>): List<String> {
        val payload = json.encodeToString(
            MergeIdsRequest.serializer(),
            MergeIdsRequest(localIds, incomingIds),
        )
        return RustBackend.call(
            "backup.merge_ids",
            payload,
            MergeIdsResult.serializer(),
        ).ids
    }

    fun validateIds(ids: List<String>): Boolean {
        val payload = json.encodeToString(
            ValidateIdsRequest.serializer(),
            ValidateIdsRequest(ids),
        )
        return RustBackend.call(
            "backup.validate_ids",
            payload,
            ValidateIdsResult.serializer(),
        ).valid
    }

    fun planRemote(entries: List<RemoteBackup>, retention: Int): RemotePlan {
        val payload = json.encodeToString(
            RemotePlanRequest.serializer(),
            RemotePlanRequest(
                entries = entries.map { RemoteEntry(it.name, it.lastModified?.toEpochMilli()) },
                retention = retention,
            ),
        )
        val result = RustBackend.call(
            "backup.plan_remote",
            payload,
            RemotePlanResult.serializer(),
        )
        return RemotePlan(result.latest, result.delete)
    }
}

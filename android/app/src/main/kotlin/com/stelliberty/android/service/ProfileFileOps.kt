package com.stelliberty.android.service

import android.content.Context
import com.stelliberty.android.data.bridge.RustBackend
import com.stelliberty.android.data.bridge.StellibertyCoreBridge
import com.stelliberty.android.domain.model.Subscription
import com.stelliberty.android.platform.ProfilePipelineKind
import com.stelliberty.android.platform.ProfileProcessingSession
import com.stelliberty.android.util.AppLogger
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.concurrent.CountDownLatch
import kotlin.concurrent.thread

@Serializable
private data class ProfileWorkDirRequest(val workDir: String)

@Serializable
private data class ProfileUuidRequest(val workDir: String, val uuid: String)

@Serializable
private data class ProfileOrphansRequest(val workDir: String, val knownUuids: List<String>)

@Serializable
private data class ProfileFileRequest(
    val workDir: String,
    val uuid: String,
    val relativePath: String,
)

@Serializable
private data class ProfileWriteFileRequest(
    val workDir: String,
    val uuid: String,
    val relativePath: String,
    val content: String,
)

@Serializable
private data class ProfilePipelineBeginRequest(
    val workDir: String,
    val uuid: String,
    val kind: String,
    val name: String,
    val isLocalFile: Boolean,
    val sourceLocation: String,
    val autoUpdateMode: String,
    val autoUpdateIntervalMinutes: Int,
)

@Serializable
private data class ProfilePipelineBeginResult(
    val token: String,
    val workDir: String,
)

@Serializable
private data class ProfilePipelineCommitRequest(val token: String, val uuid: String)

@Serializable
private data class ProfilePipelineCommitResult(
    val rootRequired: List<String> = emptyList(),
    val cleanupPaths: List<String> = emptyList(),
)

@Serializable
private data class ProfilePipelineAbortRequest(val token: String)

@Serializable
private data class RootRetryResult(
    val rootRequired: List<String> = emptyList(),
    val cleanupPaths: List<String> = emptyList(),
)

@Serializable
private data class OrphanCleanupResult(
    val orphans: List<String> = emptyList(),
    val rootRequired: List<String> = emptyList(),
    val cleanupPaths: List<String> = emptyList(),
)

@Serializable
private data class ReadImportedFileResult(val content: String? = null)

object ProfileFileOps {

    private const val TAG = "ProfileFileOps"
    private const val PROVIDERS_DIR = "providers"
    private val rustJson = Json {
        encodeDefaults = true
        explicitNulls = false
    }

    private fun getWorkDir(context: Context): File {
        val dir = File(context.filesDir, "mihomo")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    fun getImportedDir(context: Context, uuid: String): File {
        val dir = File(getWorkDir(context), "imported/$uuid")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    fun getPendingDir(context: Context, uuid: String): File {
        val dir = File(getWorkDir(context), "pending/$uuid")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    fun getSubscriptionDir(context: Context, uuid: String): File = getImportedDir(context, uuid)

    fun getSubscriptionConfigFile(context: Context, uuid: String): File =
        File(getImportedDir(context, uuid), "config.yaml")

    fun hasValidConfig(context: Context, uuid: String?): Boolean {
        if (uuid.isNullOrEmpty()) return false
        val config = File(File(getWorkDir(context), "imported/$uuid"), "config.yaml")
        return config.isFile && config.length() > 0
    }

    fun getRuntimeDir(context: Context, uuid: String): File =
        File(getWorkDir(context), "runtime/$uuid")

    fun savePendingConfig(context: Context, uuid: String, content: String): File {
        val dir = getPendingDir(context, uuid)
        val file = File(dir, "config.yaml")
        file.writeText(content)
        return file
    }

    fun releasePending(context: Context, uuid: String) {
        val pending = File(getWorkDir(context), "pending/$uuid")
        if (pending.exists()) pending.deleteRecursively()
    }

    // processing 目录全进程只有一个（路径里不带订阅编号），所以从清空到提交必须完全串行。
    // 并发两个更新会交错清空同一个目录，把一个订阅下载的配置提交进另一个订阅里。
    // 事务与阶段约束都在 Rust 侧执行；这里只负责把工作目录、编号和订阅字段传过去。
    fun beginProcessing(
        context: Context,
        uuid: String,
        kind: ProfilePipelineKind,
        subscription: Subscription,
    ): ProfileProcessingSession {
        val workDir = getWorkDir(context).absolutePath
        val payload = rustJson.encodeToString(
            ProfilePipelineBeginRequest.serializer(),
            ProfilePipelineBeginRequest(
                workDir = workDir,
                uuid = uuid,
                kind = kind.name.lowercase(),
                name = subscription.name,
                isLocalFile = subscription.isLocalFile,
                sourceLocation = subscription.sourceLocation,
                autoUpdateMode = subscription.autoUpdateMode.name.lowercase(),
                autoUpdateIntervalMinutes = subscription.autoUpdateIntervalMinutes,
            ),
        )
        val result = RustBackend.call(
            "profile.pipeline_begin",
            payload,
            ProfilePipelineBeginResult.serializer(),
        )
        return ProfileProcessingSession(result.token, result.workDir)
    }

    // 直接写文件是先清空再写入，中途断电会留下半个文件，对用户设置来说等于全部丢失。
    // 所以先写临时文件、刷到磁盘，再改名换上去——同目录改名是原子操作。
    fun writeAtomically(target: File, content: String) {
        target.parentFile?.mkdirs()
        val tmp = File(target.parentFile, "${target.name}.tmp")
        FileOutputStream(tmp).use { out ->
            out.write(content.toByteArray())
            out.fd.sync()
        }
        if (!tmp.renameTo(target)) {
            tmp.delete()
            throw IOException("rename ${tmp.name} -> ${target.name} failed")
        }
    }

    fun cleanupProcessing(context: Context) {
        val workDir = getWorkDir(context).absolutePath
        val payload = rustJson.encodeToString(
            ProfileWorkDirRequest.serializer(),
            ProfileWorkDirRequest(workDir),
        )
        val result = retryRootOwned(
            { RustBackend.call("profile.cleanup_processing", payload, RootRetryResult.serializer()) },
            { it.rootRequired },
        )
        if (result.rootRequired.isNotEmpty()) {
            AppLogger.warn(TAG, "Some interrupted commit directories remain root-owned: ${result.rootRequired}")
        }
    }

    // 先拷到临时目录再改名换上去，所有删除都排在拷贝之后：失败时原目录仍然完整——
    // 更新订阅的场景下它是唯一一份。两次改名中间挂了，靠留下的旧目录在下次启动时还原。
    fun commitProcessing(context: Context, token: String, uuid: String) {
        val payload = rustJson.encodeToString(
            ProfilePipelineCommitRequest.serializer(),
            ProfilePipelineCommitRequest(token, uuid),
        )
        val result = retryRootOwned(
            {
                RustBackend.call(
                    "profile.pipeline_commit",
                    payload,
                    ProfilePipelineCommitResult.serializer(),
                )
            },
            { it.rootRequired },
        )
        if (result.rootRequired.isNotEmpty()) {
            throw IOException("Cannot remove root-owned commit directories: ${result.rootRequired}")
        }
        result.cleanupPaths.forEach { path ->
            if (!RootHelper.rmRfAsRoot(path)) {
                AppLogger.warn(TAG, "Failed to remove old imported copy: $path")
            }
        }
    }

    fun abortProcessing(token: String) {
        val payload = rustJson.encodeToString(
            ProfilePipelineAbortRequest.serializer(),
            ProfilePipelineAbortRequest(token),
        )
        RustBackend.call("profile.pipeline_abort", payload, Unit.serializer())
    }

    private fun <T> retryRootOwned(block: () -> T, paths: (T) -> List<String>): T {
        var result = block()
        repeat(2) {
            val required = paths(result)
            if (required.isEmpty()) return result
            AppLogger.warn(TAG, "Removing root-owned profile paths: $required")
            required.forEach { path ->
                if (!RootHelper.rmRfAsRoot(path)) {
                    AppLogger.warn(TAG, "Root removal failed: $path")
                }
            }
            result = block()
        }
        return result
    }

    private fun removeMaybeRootOwned(dir: File) {
        if (dir.exists() && !dir.deleteRecursively()) RootHelper.rmRfAsRoot(dir.absolutePath)
    }

    fun deleteProfileDirs(context: Context, uuid: String) {
        val workDir = getWorkDir(context).absolutePath
        val payload = rustJson.encodeToString(
            ProfileUuidRequest.serializer(),
            ProfileUuidRequest(workDir, uuid),
        )
        val result = retryRootOwned(
            { RustBackend.call("profile.delete_profile_dirs", payload, RootRetryResult.serializer()) },
            { it.rootRequired },
        )
        if (result.rootRequired.isNotEmpty()) {
            AppLogger.warn(TAG, "Some profile directories remain root-owned: ${result.rootRequired}")
        }
    }

    // 删订阅是「先删列表条目、再删目录」两步，中间进程挂了就留下永远没人认领的目录。
    // 只有订阅列表知道哪些还算数，所以按现存的编号反着扫。
    fun deleteOrphanProfileDirs(context: Context, knownUuids: Set<String>): List<String> {
        val workDir = getWorkDir(context).absolutePath
        val payload = rustJson.encodeToString(
            ProfileOrphansRequest.serializer(),
            ProfileOrphansRequest(workDir, knownUuids.toList()),
        )
        val result = retryRootOwned(
            { RustBackend.call("profile.delete_orphan_dirs", payload, OrphanCleanupResult.serializer()) },
            { it.rootRequired },
        )
        if (result.rootRequired.isNotEmpty()) {
            AppLogger.warn(TAG, "Some orphan directories remain root-owned: ${result.rootRequired}")
        }
        return result.orphans
    }

    // ROOT 模式下 mihomo 以 root 身份运行，会往工作目录里写缓存文件，普通权限删不掉。
    // 所以给它单独一份运行目录，正式目录永远保持应用自己的权限。
    fun prepareRootRuntime(context: Context, uuid: String): File {
        val imported = File(getWorkDir(context), "imported/$uuid")
        val runtime = getRuntimeDir(context, uuid)
        clearRootRuntime(runtime)
        runtime.mkdirs()
        // 地理数据随后重新链接，复制会顺着链接白拷几十 MB。
        imported.listFiles()?.filter { it.name !in GEODATA_FILES && it.name != PROVIDERS_DIR }?.forEach {
            it.copyRecursively(File(runtime, it.name), overwrite = true)
        }
        seedRootProviders(File(imported, PROVIDERS_DIR), File(runtime, PROVIDERS_DIR))
        ensureGeodataLinks(context, runtime)
        return runtime
    }

    // provider 缓存跨启动保留，否则每次启动都要在就绪前同步重新下载全部 provider。
    fun cleanupRootRuntime(context: Context, uuid: String) {
        clearRootRuntime(getRuntimeDir(context, uuid))
    }

    private fun clearRootRuntime(runtime: File) {
        runtime.listFiles()?.filter { it.name != PROVIDERS_DIR }?.forEach(::removeMaybeRootOwned)
    }

    // 更新订阅会重下全部 provider，导入文件较新时替换，与 VPN 模式直接读导入目录一致；保留修改时间供内核判断过期。
    // 内核自建的子目录归 root 所有、应用写不进去，这时沿用运行目录里的文件。
    private fun seedRootProviders(source: File, target: File) {
        source.walkTopDown().filter { it.isFile }.forEach { file ->
            val dest = File(target, file.relativeTo(source).path)
            if (dest.exists() && dest.lastModified() >= file.lastModified()) return@forEach
            runCatching {
                file.copyTo(dest, overwrite = true)
                dest.setLastModified(file.lastModified())
            }
        }
    }

    fun cleanupAllRootRuntime(context: Context) {
        val runtime = File(getWorkDir(context), "runtime")
        if (!runtime.exists()) return
        if (!runtime.deleteRecursively()) {
            RootHelper.rmRfAsRoot(runtime.absolutePath)
        }
    }

    fun listImportedFiles(context: Context, uuid: String): List<String> {
        val workDir = getWorkDir(context).absolutePath
        val payload = rustJson.encodeToString(
            ProfileUuidRequest.serializer(),
            ProfileUuidRequest(workDir, uuid),
        )
        return RustBackend.call(
            "profile.list_imported_files",
            payload,
            ListSerializer(String.serializer()),
        )
    }

    fun readImportedFile(context: Context, uuid: String, relativePath: String): String? {
        val workDir = getWorkDir(context).absolutePath
        val payload = rustJson.encodeToString(
            ProfileFileRequest.serializer(),
            ProfileFileRequest(workDir, uuid, relativePath),
        )
        val result = RustBackend.call(
            "profile.read_imported_file",
            payload,
            ReadImportedFileResult.serializer(),
        )
        return result.content
    }

    fun writeImportedFile(context: Context, uuid: String, relativePath: String, content: String) {
        val workDir = getWorkDir(context).absolutePath
        val payload = rustJson.encodeToString(
            ProfileWriteFileRequest.serializer(),
            ProfileWriteFileRequest(workDir, uuid, relativePath, content),
        )
        RustBackend.call("profile.write_imported_file", payload, Unit.serializer())
    }

    internal val GEODATA_FILES = listOf(
        "geoip.metadb",
        "Country.mmdb", "country.mmdb",
        "geoip.dat", "GeoIP.dat",
        "geosite.dat", "GeoSite.dat",
        "ASN.mmdb", "asn.mmdb",
    )

    fun getGeodataDir(context: Context): File {
        val dir = File(getWorkDir(context), "geodata")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    // 与 assets 里的「文件名.xz」一一对应。
    private val BUNDLED_GEODATA = listOf("geoip.metadb", "GeoIP.dat", "geosite.dat", "ASN.mmdb")
    private val geodataReady = CountDownLatch(1)

    // 安装或升级后的首次启动才真正解压，要一两秒，只能在后台线程调用。
    fun extractGeodata(context: Context) {
        try {
            val dir = getGeodataDir(context)
            val apkPath = context.applicationInfo.sourceDir
            val installedAt = context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime
            val stale = BUNDLED_GEODATA.filter { name ->
                val target = File(dir, name)
                !target.exists() || target.lastModified() < installedAt
            }
            if (stale.isEmpty()) return
            val startedAt = System.currentTimeMillis()
            // 解压是单线程 CPU 密集，逐个做要多等几倍；峰值内存约为各文件体积之和。
            stale.map { name -> thread(name = "geodata-$name") { extractBundledGeodata(dir, apkPath, name) } }
                .forEach { it.join() }
            AppLogger.info(TAG, "Extracted $stale in ${System.currentTimeMillis() - startedAt}ms")
        } finally {
            geodataReady.countDown()
        }
    }

    private fun extractBundledGeodata(dir: File, apkPath: String, name: String) {
        // 先写 .part 再改名：中途被杀不会留下半截文件，下次启动会重新解压。
        val partial = File(dir, "$name.part")
        runCatching {
            StellibertyCoreBridge.extractXzAsset(apkPath, "assets/$name.xz", partial)
            Files.move(partial.toPath(), File(dir, name).toPath(), StandardCopyOption.REPLACE_EXISTING)
        }.onFailure { e ->
            partial.delete()
            AppLogger.error(TAG, "Failed to extract $name", e)
        }
    }

    // 读地理数据之前调用，解压未完成时阻塞，调用方须在后台线程。
    fun awaitGeodata() = geodataReady.await()

    fun ensureGeodataLinks(context: Context, subscriptionDir: File) {
        awaitGeodata()
        val geodataDir = getGeodataDir(context)
        for (fileName in GEODATA_FILES) {
            val source = File(geodataDir, fileName)
            if (!source.exists()) continue
            val target = File(subscriptionDir, fileName).toPath()
            if (Files.isSymbolicLink(target) && Files.exists(target)) continue
            // 工作目录里的实体文件是 mihomo 自己下载的，可能是被中断的残片，校验失败后它会在启动时阻塞重下。
            Files.deleteIfExists(target)
            runCatching { Files.createSymbolicLink(target, source.toPath()) }
                .onFailure { AppLogger.warn(TAG, "Failed to link $fileName into ${subscriptionDir.name}", it) }
        }
    }
}

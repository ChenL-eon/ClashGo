package com.clashgo.android.data.repository

import android.content.Context
import com.clashgo.android.data.bridge.ClashGoCoreBridge
import com.clashgo.android.data.store.ProfileTransformWriter
import com.clashgo.android.domain.model.OfflineProxySnapshot
import com.clashgo.android.domain.repository.SubscriptionRepository
import com.clashgo.android.service.ProfileFileOps
import com.clashgo.android.util.AppLogger
import com.clashgo.android.util.describe
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class OfflineProxyData(
    val snapshot: OfflineProxySnapshot,
    val workDir: File,
    val transformPath: File?,
    val ageSecretKey: String,
)

// 停止态代理页的数据来源：订阅配置、覆写与 provider 缓存都在磁盘上，解析到与内核 REST 同形的结果。
class OfflineProxyRepository(
    private val context: Context,
    private val subscriptions: SubscriptionRepository,
    private val transformWriter: ProfileTransformWriter,
) {

    suspend fun load(uuid: String): Result<OfflineProxyData> = withContext(Dispatchers.IO) {
        runCatching {
            val subscription = subscriptions.subscriptions.value.firstOrNull { it.id == uuid }
                ?: error("subscription $uuid not found")
            val workDir = ProfileFileOps.getSubscriptionDir(context, uuid)
            if (!File(workDir, "config.yaml").isFile) error("config.yaml not found")
            val transformPath = transformWriter.writeRuntime(subscription)?.let(::File)
            val snapshot = ClashGoCoreBridge.offlineProxySnapshot(
                workDir = workDir,
                transform = transformPath,
                ageSecretKey = subscription.ageSecretKey,
            )
            OfflineProxyData(snapshot, workDir, transformPath, subscription.ageSecretKey)
        }.onFailure {
            AppLogger.warn(TAG, "load offline proxies failed", it)
        }
    }

    suspend fun testDelays(
        data: OfflineProxyData,
        nodes: Collection<String>,
        testUrl: String = "http://www.gstatic.com/generate_204",
        timeout: Int = 5000,
    ): Result<Map<String, Int>> = withContext(Dispatchers.IO) {
        runCatching {
            ClashGoCoreBridge.testOfflineDelays(
                workDir = data.workDir,
                transform = data.transformPath,
                ageSecretKey = data.ageSecretKey,
                nodes = nodes,
                testUrl = testUrl,
                timeout = timeout,
            )
        }.onFailure {
            AppLogger.warn(TAG, "test offline delays failed: ${it.describe()}", it)
        }
    }

    companion object {
        private const val TAG = "OfflineProxy"
    }
}

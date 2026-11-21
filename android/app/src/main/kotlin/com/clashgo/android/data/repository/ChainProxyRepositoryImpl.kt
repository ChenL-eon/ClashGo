package com.clashgo.android.data.repository

import com.clashgo.android.data.bridge.ClashGoCoreBridge
import com.clashgo.android.data.bridge.ClashGoCoreError
import com.clashgo.android.data.store.ProfileTransformWriter
import com.clashgo.android.data.store.SubscriptionStore
import com.clashgo.android.domain.model.ChainProxyContext
import com.clashgo.android.domain.model.Subscription
import com.clashgo.android.domain.model.SubscriptionCustomChainProxy
import com.clashgo.android.domain.repository.ChainProxyRepository
import com.clashgo.android.platform.ProfileFileManager
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

// 保存持 processLock，校验与写入之间订阅配置和覆写文件保持一致；读取候选项只读文件，不占这把锁。
class ChainProxyRepositoryImpl(
    private val subscriptionStore: SubscriptionStore,
    private val subscriptions: SubscriptionRepositoryImpl,
    private val transformWriter: ProfileTransformWriter,
    private val fileManager: ProfileFileManager,
) : ChainProxyRepository {

    private val contextLock = Mutex()

    override suspend fun loadContext(subscriptionId: String): ChainProxyContext = contextLock.withLock {
        withContext(Dispatchers.IO) {
            val subscription = find(subscriptionId)
            val transform = transformWriter.write(subscription, CONTEXT_TRANSFORM, withChains = false, rules = null)
            try {
                ClashGoCoreBridge.chainProxyContext(
                    workDir = File(fileManager.getImportedDir(subscription.id)),
                    transform = transform?.let(::File),
                    ageSecretKey = subscription.ageSecretKey,
                )
            } finally {
                transform?.let { File(it).delete() }
            }
        }
    }

    override suspend fun save(
        subscriptionId: String,
        disabledBuiltinNames: List<String>,
        customChainProxies: List<SubscriptionCustomChainProxy>,
    ): Boolean = ProfileProcessor.withProcessLock {
        val candidate = find(subscriptionId).copy(
            disabledBuiltinChainProxyNames = disabledBuiltinNames,
            customChainProxies = customChainProxies,
        )
        val hasCycle = validate(candidate)
        subscriptions.setChainProxies(subscriptionId, disabledBuiltinNames, customChainProxies)
        hasCycle
    }

    private suspend fun validate(subscription: Subscription): Boolean = withContext(Dispatchers.IO) {
        val transform = transformWriter.write(subscription, VALIDATE_TRANSFORM) ?: return@withContext false
        try {
            ClashGoCoreBridge.validateTransform(
                workDir = File(fileManager.getImportedDir(subscription.id)),
                transform = File(transform),
                ageSecretKey = subscription.ageSecretKey,
            )
        } catch (e: ClashGoCoreError) {
            throw ConfigValidationException(e.message.orEmpty().removePrefix("validate config:").trim())
        } finally {
            File(transform).delete()
        }
    }

    private fun find(id: String): Subscription =
        subscriptionStore.findImported(id) ?: throw IllegalArgumentException("Profile $id not found")

    private companion object {
        const val CONTEXT_TRANSFORM = "chain.context.json"
        const val VALIDATE_TRANSFORM = "chain.validate.json"
    }
}

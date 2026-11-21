package com.clashgo.android.data.repository

import com.clashgo.android.data.bridge.ClashGoCoreBridge
import com.clashgo.android.data.bridge.ClashGoCoreError
import com.clashgo.android.data.store.ProfileTransformWriter
import com.clashgo.android.data.store.RuleOverrideStore
import com.clashgo.android.data.store.SubscriptionStore
import com.clashgo.android.domain.model.EditableRule
import com.clashgo.android.domain.model.RuleOverrideContext
import com.clashgo.android.domain.model.RuleOverrideSet
import com.clashgo.android.domain.model.RuleTemplate
import com.clashgo.android.domain.model.Subscription
import com.clashgo.android.domain.repository.RuleOverrideRepository
import com.clashgo.android.platform.ProfileFileManager
import java.io.File
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

// 保存持 processLock，校验与写入之间订阅配置和覆写文件保持一致；读取基线只读文件，不占这把锁。
class RuleOverrideRepositoryImpl(
    private val store: RuleOverrideStore,
    private val subscriptionStore: SubscriptionStore,
    private val transformWriter: ProfileTransformWriter,
    private val fileManager: ProfileFileManager,
) : RuleOverrideRepository {

    private val contextLock = Mutex()

    override val templates: Flow<List<RuleTemplate>> = store.templates

    override fun observe(subscriptionId: String): Flow<RuleOverrideSet> = store.observe(subscriptionId)

    override fun find(subscriptionId: String): RuleOverrideSet = store.find(subscriptionId)

    override suspend fun loadContext(subscriptionId: String): RuleOverrideContext = contextLock.withLock {
        withContext(Dispatchers.IO) {
            val subscription = subscription(subscriptionId)
            val transform = transformWriter.write(subscription, CONTEXT_TRANSFORM, rules = null)
            try {
                ClashGoCoreBridge.ruleContext(
                    workDir = File(fileManager.getImportedDir(subscription.id)),
                    transform = transform?.let(::File),
                    ageSecretKey = subscription.ageSecretKey,
                )
            } finally {
                transform?.let { File(it).delete() }
            }
        }
    }

    override suspend fun save(set: RuleOverrideSet) = ProfileProcessor.withProcessLock {
        validate(subscription(set.subscriptionId), set)
        store.save(set)
    }

    @OptIn(ExperimentalUuidApi::class)
    override suspend fun saveTemplate(name: String, rules: List<EditableRule>) {
        val trimmed = name.trim()
        val existing = store.templates().firstOrNull { it.name.equals(trimmed, ignoreCase = true) }
        store.upsertTemplate(RuleTemplate(existing?.id ?: "template-${Uuid.random().toHexString()}", trimmed, rules))
    }

    override suspend fun deleteTemplate(id: String) = store.deleteTemplate(id)

    private suspend fun validate(subscription: Subscription, set: RuleOverrideSet) = withContext(Dispatchers.IO) {
        val transform = transformWriter.write(subscription, VALIDATE_TRANSFORM, rules = set) ?: return@withContext
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

    private fun subscription(id: String): Subscription =
        subscriptionStore.findImported(id) ?: throw IllegalArgumentException("Profile $id not found")

    private companion object {
        const val CONTEXT_TRANSFORM = "rule.context.json"
        const val VALIDATE_TRANSFORM = "rule.validate.json"
    }
}

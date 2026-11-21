package com.clashgo.android.data.repository

import com.clashgo.android.data.bridge.RustBackend
import com.clashgo.android.domain.model.Subscription
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
private data class UpdatePlanRequest(
    val now: Long,
    val minIntervalMinutes: Int,
    val subscriptions: List<UpdatePlanSubscription>,
)

@Serializable
private data class UpdatePlanSubscription(
    val id: String,
    val isLocalFile: Boolean,
    val autoUpdateMode: String,
    val autoUpdateIntervalMinutes: Int,
    val createdAt: Long,
    val lastUpdatedAt: Long? = null,
    val lastErrorAt: Long? = null,
)

@Serializable
data class UpdatePlanItem(
    val id: String,
    val dueAtMillis: Long,
    val due: Boolean,
)

@Serializable
private data class UpdatePlanResult(val items: List<UpdatePlanItem> = emptyList())

// 闹钟集合完全由订阅列表推导；这里只把绝对触发点交给 AlarmManager，什么时候该响由 Rust 决定。
internal object UpdateSchedule {

    private val json = Json {
        encodeDefaults = true
        explicitNulls = false
        ignoreUnknownKeys = true
    }

    fun plan(
        subscriptions: List<Subscription>,
        nowMillis: Long,
        minIntervalMinutes: Int = MIN_AUTO_UPDATE_INTERVAL_MINUTES,
    ): List<UpdatePlanItem> {
        val payload = json.encodeToString(
            UpdatePlanRequest.serializer(),
            UpdatePlanRequest(
                now = nowMillis,
                minIntervalMinutes = minIntervalMinutes,
                subscriptions = subscriptions.map { it.toPlanSubscription() },
            ),
        )
        return RustBackend.call(
            "update.plan",
            payload,
            UpdatePlanResult.serializer(),
        ).items
    }

    fun isDue(
        subscription: Subscription,
        nowMillis: Long,
        minIntervalMinutes: Int = MIN_AUTO_UPDATE_INTERVAL_MINUTES,
    ): Boolean = plan(listOf(subscription), nowMillis, minIntervalMinutes)
        .firstOrNull { it.id == subscription.id }
        ?.due == true

    private fun Subscription.toPlanSubscription() = UpdatePlanSubscription(
        id = id,
        isLocalFile = isLocalFile,
        autoUpdateMode = autoUpdateMode.name.lowercase(),
        autoUpdateIntervalMinutes = autoUpdateIntervalMinutes,
        createdAt = createdAt.toEpochMilliseconds(),
        lastUpdatedAt = lastUpdatedAt?.toEpochMilliseconds(),
        lastErrorAt = lastErrorAt?.toEpochMilliseconds(),
    )
}

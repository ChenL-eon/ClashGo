package com.stelliberty.android.data.repository

import com.stelliberty.android.data.bridge.RustBackend
import com.stelliberty.android.data.bridge.RustBackendException
import com.stelliberty.android.domain.model.Subscription
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
private data class SubscriptionValidationRequest(
    val name: String,
    val isLocalFile: Boolean,
    val sourceLocation: String,
    val autoUpdateMode: String,
    val autoUpdateIntervalMinutes: Int,
)

@Serializable
private data class SubscriptionValidationResult(val needsFetch: Boolean = false)

// 与旧 Subscription.enforceFieldValid 相同的规则；放在 Rust 后，导入与编辑保存共用同一份判断。
internal object SubscriptionValidation {

    private val json = Json {
        encodeDefaults = true
        explicitNulls = false
    }

    fun validate(subscription: Subscription): Boolean {
        val payload = json.encodeToString(
            SubscriptionValidationRequest.serializer(),
            SubscriptionValidationRequest(
                name = subscription.name,
                isLocalFile = subscription.isLocalFile,
                sourceLocation = subscription.sourceLocation,
                autoUpdateMode = subscription.autoUpdateMode.name.lowercase(),
                autoUpdateIntervalMinutes = subscription.autoUpdateIntervalMinutes,
            ),
        )
        return try {
            RustBackend.call(
                "profile.validate_subscription",
                payload,
                SubscriptionValidationResult.serializer(),
            ).needsFetch
        } catch (e: RustBackendException) {
            throw translate(e, subscription)
        }
    }

    fun translate(error: RustBackendException, subscription: Subscription? = null): Throwable {
        if (error.code != "profile_validation") return error
        return when (error.detail) {
            "invalid_name" -> ImportError.InvalidName()
            "invalid_scheme" -> ImportError.InvalidScheme(subscription?.sourceLocation.orEmpty())
            "interval_too_small" -> ImportError.IntervalTooSmall()
            else -> error
        }
    }
}
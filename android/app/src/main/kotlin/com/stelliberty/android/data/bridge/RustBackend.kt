package com.stelliberty.android.data.bridge

import com.stelliberty.android.util.AppLogger
import com.stelliberty.android.util.describe
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

class RustBackendException(
    val code: String,
    message: String,
    val detail: String? = null,
) : RuntimeException(message)

class RustBackendUnavailableException(message: String, cause: Throwable?) : RuntimeException(message, cause)

@Serializable
private data class BackendErrorBody(
    val code: String = "unknown",
    val message: String = "",
    val detail: String? = null,
)

@Serializable
private data class BackendEnvelope<T>(
    val ok: Boolean = false,
    val data: T? = null,
    val error: BackendErrorBody? = null,
)

@Serializable
private data class BackendInfo(
    val version: String = "",
    val arch: String = "",
    val workDir: String? = null,
)

// Rust 后端唯一入口：方法名做路由，JSON 信封做结果与错误，避免每加一个能力就多一个 JNI 符号。
object RustBackend {

    private const val TAG = "RustBackend"

    private val json = Json { ignoreUnknownKeys = true }

    // 加载失败只降级，不在这里抛：调用方决定是回退旧实现还是报错。
    private val loadError: Throwable? = runCatching { System.loadLibrary("stelliberty_backend") }.exceptionOrNull()

    @Volatile
    private var initError: Throwable? = null

    val isAvailable: Boolean
        get() = loadError == null && initError == null

    fun init(workDir: String) {
        val loadError = loadError
        if (loadError != null) {
            initError = loadError
            AppLogger.warn(TAG, "Rust backend library unavailable; keeping Kotlin implementations", loadError)
            return
        }
        try {
            val raw = nativeInit(workDir) ?: throw IllegalStateException("nativeInit returned null")
            val envelope = json.decodeFromString(BackendEnvelope.serializer(BackendInfo.serializer()), raw)
            val info = envelope.data
            if (!envelope.ok || info == null) {
                throw IllegalStateException(envelope.error?.message ?: "nativeInit failed")
            }
            AppLogger.info(
                TAG,
                "Rust backend ready: version=${info.version}, arch=${info.arch}, workDir=${info.workDir}",
            )
        } catch (t: Throwable) {
            initError = t
            AppLogger.warn(TAG, "Rust backend init failed; keeping Kotlin implementations", t)
        }
    }

    fun <T> call(method: String, payload: String, serializer: KSerializer<T>): T {
        ensureReady()
        val raw = try {
            nativeCall(method, payload)
        } catch (t: Throwable) {
            throw RustBackendException("jni", "native call failed: ${t.describe()}")
        } ?: throw RustBackendException("jni", "native call returned null")

        val envelope = try {
            json.decodeFromString(BackendEnvelope.serializer(serializer), raw)
        } catch (t: Throwable) {
            throw RustBackendException("protocol", "invalid backend response: ${t.describe()}", raw)
        }
        if (!envelope.ok) {
            val error = envelope.error
            throw RustBackendException(
                code = error?.code ?: "unknown",
                message = error?.message ?: "native backend error",
                detail = error?.detail,
            )
        }
        return envelope.data ?: throw RustBackendException("protocol", "backend returned empty data")
    }

    private fun ensureReady() {
        val error = loadError ?: initError
        if (error != null) throw RustBackendUnavailableException("Rust backend unavailable", error)
    }

    @JvmStatic
    private external fun nativeInit(workDir: String): String?

    @JvmStatic
    private external fun nativeCall(method: String, payload: String): String?
}

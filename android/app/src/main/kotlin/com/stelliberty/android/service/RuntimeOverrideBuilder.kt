package com.stelliberty.android.service

import android.content.Context
import com.stelliberty.android.data.bridge.RustBackend
import com.stelliberty.android.domain.model.AppProxyMode
import com.stelliberty.android.domain.model.ConfigurationOverride
import com.stelliberty.android.platform.PlatformStorage
import com.stelliberty.android.platform.StorageKeys
import com.stelliberty.android.platform.TunMode
import com.stelliberty.android.service.RuntimeOverrideBuilder.DEFAULT_MIXED_PORT
import com.stelliberty.android.util.AppLogger
import java.io.File
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

object RuntimeOverrideBuilder {

    private const val TAG = "RuntimeOverride"
    internal const val DEFAULT_TUN_DEVICE = "Stelliberty"

    // VPN 模式下这个值必须和 VpnService 设的 MTU 一致：网卡底层用它算读缓冲，两边不一致或为 0 时
    // 所有读取都会失败，表现成「延迟测得出来但完全上不了网」。两边共用这个常量，谁都不要写死数字。
    internal const val VPN_TUN_MTU = 9000

    internal const val ROOT_TUN_TABLE = 2022
    internal const val ROOT_TUN_RULE_INDEX = 9000

    internal const val DEFAULT_MIXED_PORT = 7890

    private const val RUST_METHOD = "runtime_override.build"

    // 真正参与运行参数合并的是 Rust；Kotlin 只读平台设置、TUN fd 与常量。
    private val rustJson = Json {
        encodeDefaults = true
        explicitNulls = false
    }

    fun buildAndWriteForRun(
        context: Context,
        userOverride: ConfigurationOverride,
        tunFd: Int,
        tunMode: TunMode,
        mixedPortRequired: Boolean,
        subscriptionMixedPort: Int?,
        tproxyForTether: Boolean = false,
    ): File {
        val storage = PlatformStorage(context)
        val request = RuntimeOverrideRequest(
            workDir = ConfigGenerator.getWorkDir(context).absolutePath,
            tunMode = tunMode.storageValue,
            tunFd = tunFd,
            mixedPortRequired = mixedPortRequired,
            subscriptionMixedPort = subscriptionMixedPort,
            tproxyForTether = tproxyForTether,
            wifiRuntimeMode = storage.getString(StorageKeys.WIFI_POLICY_RUNTIME_MODE, "")
                .takeIf { it == "rule" || it == "global" || it == "direct" },
            userOverride = userOverride,
            platform = RuntimeOverridePlatform(
                vpnTunMtu = VPN_TUN_MTU,
                defaultMixedPort = DEFAULT_MIXED_PORT,
                rootTproxyPort = RootTproxyApplier.TPROXY_PORT,
                rootTetherTproxyPort = RootTetherHijacker.TPROXY_PORT,
                rootDnsPort = RootDnsHijacker.PORT,
                rootTunTableIndex = ROOT_TUN_TABLE,
                rootTunRuleIndex = ROOT_TUN_RULE_INDEX,
                intranetRoutesV4 = IptablesIntranet.V4,
                intranetRoutesV6 = IptablesIntranet.V6,
            ),
            app = RuntimeOverrideApp(
                selfPackage = context.packageName,
                appProxyMode = AppProxyMode.parse(storage.getString(StorageKeys.APP_PROXY_MODE, "")).name,
                appProxyPackages = storage.getStringSet(StorageKeys.APP_PROXY_PACKAGES, emptySet()).toList(),
                allowIpv6 = storage.getString(StorageKeys.VPN_ALLOW_IPV6, "false") == "true",
                rootTunDevice = storage.getString(StorageKeys.ROOT_TUN_DEVICE, DEFAULT_TUN_DEVICE),
                rootTunJumboMtu = storage.getString(StorageKeys.ROOT_TUN_JUMBO_MTU, "true") == "true",
            ),
        )
        val result = RustBackend.call(
            method = RUST_METHOD,
            payload = rustJson.encodeToString(RuntimeOverrideRequest.serializer(), request),
            serializer = RuntimeOverrideResult.serializer(),
        )
        AppLogger.info(
            TAG,
            "Runtime override for $tunMode: ${result.summary}; " +
                "includePackages=${result.includePackages}, excludePackages=${result.excludePackages}",
        )
        return File(result.path)
    }

    // 内核实际监听的 mixed-port：用户设置 > 订阅自带 > 需要时补默认值；null 表示不监听（含用户设 0）。
    // 订阅自带的值靠行扫描取得；覆写改了该端口时内核以覆写为准，这里取不到。
    fun resolveMixedPort(
        userOverride: ConfigurationOverride,
        subscriptionMixedPort: Int?,
        mixedPortRequired: Boolean,
    ): Int? = (userOverride.mixedPort ?: subscriptionMixedPort ?: DEFAULT_MIXED_PORT.takeIf { mixedPortRequired })
        ?.takeIf { it > 0 }
}

@Serializable
private data class RuntimeOverridePlatform(
    val vpnTunMtu: Int,
    val defaultMixedPort: Int,
    val rootTproxyPort: Int,
    val rootTetherTproxyPort: Int,
    val rootDnsPort: Int,
    val rootTunTableIndex: Int,
    val rootTunRuleIndex: Int,
    val intranetRoutesV4: List<String>,
    val intranetRoutesV6: List<String>,
)

@Serializable
private data class RuntimeOverrideApp(
    val selfPackage: String,
    val appProxyMode: String,
    val appProxyPackages: List<String>,
    val allowIpv6: Boolean,
    val rootTunDevice: String,
    val rootTunJumboMtu: Boolean,
)

@Serializable
private data class RuntimeOverrideRequest(
    val workDir: String,
    val tunMode: String,
    val tunFd: Int,
    val mixedPortRequired: Boolean,
    val subscriptionMixedPort: Int?,
    val tproxyForTether: Boolean,
    val wifiRuntimeMode: String?,
    val userOverride: ConfigurationOverride,
    val platform: RuntimeOverridePlatform,
    val app: RuntimeOverrideApp,
)

@Serializable
private data class RuntimeOverrideResult(
    val path: String,
    val includePackages: Int = 0,
    val excludePackages: Int = 0,
    val summary: String = "",
)

package com.clashgo.android.domain.model

import kotlinx.serialization.Serializable

// 与运行时 /proxies、/group、/providers/proxies 同形，离线代理页直接复用同一套映射。
@Serializable
data class OfflineProxySnapshot(
    val mode: String = "",
    val proxies: Map<String, ProxyNode> = emptyMap(),
    val groups: List<ProxyNode> = emptyList(),
    val providers: Map<String, ProviderInfo> = emptyMap(),
)

package com.clashgo.android.viewmodel

import androidx.lifecycle.ViewModel
import com.clashgo.android.data.repository.OverrideJsonStore
import com.clashgo.android.domain.model.ConfigurationOverride
import com.clashgo.android.domain.model.DelayTestUrl
import com.clashgo.android.domain.model.DnsOverride
import com.clashgo.android.domain.model.SnifferOverride
import com.clashgo.android.platform.PlatformStorage
import com.clashgo.android.platform.StorageKeys
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

// 「Clash 特性」下各页共用：字段都在 override.user.json 里，按页拆分只影响展示。
// 延迟检测链接是应用偏好而非内核覆写，单独存在 PlatformStorage。
class ClashFeaturesViewModel(
    private val store: OverrideJsonStore,
    private val storage: PlatformStorage,
) : ViewModel() {

    val state: StateFlow<ConfigurationOverride> = store.state

    private val _delayTestUrl = MutableStateFlow(loadDelayTestUrl())
    val delayTestUrl: StateFlow<String> = _delayTestUrl.asStateFlow()

    fun updateDelayTestUrl(url: String?) {
        val value = DelayTestUrl.normalize(url)
        _delayTestUrl.value = value
        storage.putString(StorageKeys.DELAY_TEST_URL, value)
    }

    private fun loadDelayTestUrl(): String =
        DelayTestUrl.normalize(storage.getString(StorageKeys.DELAY_TEST_URL, DelayTestUrl.DEFAULT))

    fun update(transform: (ConfigurationOverride) -> ConfigurationOverride) {
        store.update(transform)
    }

    // 子对象全部字段回到未修改时整体置空，避免写出空的 dns / sniffer 段。
    fun updateDns(transform: (DnsOverride) -> DnsOverride) {
        store.update { state ->
            val next = transform(state.dns ?: DnsOverride())
            state.copy(dns = next.takeIf { it != DnsOverride() })
        }
    }

    fun updateSniffer(transform: (SnifferOverride) -> SnifferOverride) {
        store.update { state ->
            val next = transform(state.sniffer ?: SnifferOverride())
            state.copy(sniffer = next.takeIf { it != SnifferOverride() })
        }
    }
}

package com.clashgo.android.domain.model

// 代理页与定时测速共用同一个检测地址；留空或格式不对时退回默认，避免把非法 URL 交给内核。
object DelayTestUrl {
    const val GSTATIC = "https://www.gstatic.com/generate_204"
    const val CLOUDFLARE = "https://cp.cloudflare.com/generate_204"
    const val DEFAULT = GSTATIC

    val presets = listOf(GSTATIC, CLOUDFLARE)

    private val httpUrl = Regex("^https?://\\S+$", RegexOption.IGNORE_CASE)

    // 旧版默认值是 HTTP：统一延迟发第二次 HEAD 时若被 HTTP 劫持，mihomo 会退回首次耗时。
    // 只迁移两个旧预设，自定义 HTTP 地址仍按用户选择保留。
    private val legacyPresets = mapOf(
        "http://www.gstatic.com/generate_204" to GSTATIC,
        "http://cp.cloudflare.com/generate_204" to CLOUDFLARE,
    )

    fun normalize(value: String?): String {
        val url = value?.trim().orEmpty()
        if (!httpUrl.matches(url)) return DEFAULT
        return legacyPresets.entries
            .firstOrNull { it.key.equals(url, ignoreCase = true) }
            ?.value ?: url
    }

    fun isCustom(value: String): Boolean = value !in presets
}

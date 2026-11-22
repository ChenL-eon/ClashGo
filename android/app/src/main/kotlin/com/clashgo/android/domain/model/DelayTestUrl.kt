package com.clashgo.android.domain.model

// 代理页与定时测速共用同一个检测地址；留空或格式不对时退回默认，避免把非法 URL 交给内核。
object DelayTestUrl {
    const val GSTATIC = "http://www.gstatic.com/generate_204"
    const val CLOUDFLARE = "http://cp.cloudflare.com/generate_204"
    const val DEFAULT = GSTATIC

    val presets = listOf(GSTATIC, CLOUDFLARE)

    private val httpUrl = Regex("^https?://\\S+$", RegexOption.IGNORE_CASE)

    fun normalize(value: String?): String {
        val url = value?.trim().orEmpty()
        return if (httpUrl.matches(url)) url else DEFAULT
    }

    fun isCustom(value: String): Boolean = value !in presets
}

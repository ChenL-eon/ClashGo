package com.clashgo.android.util

fun Throwable.describe(): String =
    message?.takeIf { it.isNotBlank() } ?: this::class.simpleName ?: "Unknown error"

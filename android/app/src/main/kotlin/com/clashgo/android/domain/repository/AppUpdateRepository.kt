package com.clashgo.android.domain.repository

import com.clashgo.android.domain.model.AppUpdateResult
import com.clashgo.android.domain.model.UpdateChannel

interface AppUpdateRepository {
    suspend fun checkForUpdate(currentVersion: String, channel: UpdateChannel): AppUpdateResult
}

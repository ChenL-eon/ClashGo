package com.clashgo.android.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.clashgo.android.data.api.AutoDelayTester
import org.koin.core.context.GlobalContext

class AutoDelayReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        GlobalContext.get().get<AutoDelayTester>().onAlarm()
    }
}

package com.clashgo.android.di

import com.clashgo.android.data.backup.BackupManager
import com.clashgo.android.platform.AppListProvider
import com.clashgo.android.platform.AutoDelayAlarm
import com.clashgo.android.platform.BootStartManager
import com.clashgo.android.platform.PlatformStorage
import com.clashgo.android.platform.ProxyServiceController
import com.clashgo.android.platform.WifiPolicyController
import com.clashgo.android.service.ProfileUpdateScheduler
import com.clashgo.android.service.ProfileUpdateTask
import org.koin.android.ext.koin.androidContext
import org.koin.core.module.Module
import org.koin.dsl.module

val androidPlatformModule: Module = module {
    single { AutoDelayAlarm(androidContext()) }
    single { PlatformStorage(androidContext()) }
    single { ProxyServiceController(androidContext(), get()) }
    single { AppListProvider(androidContext()) }
    single { WifiPolicyController(androidContext()) }
    single { BootStartManager(androidContext()) }
    factory { ProfileUpdateTask(get(), get(), get(), get()) }
    single {
        BackupManager(
            context = androidContext(),
            storage = get(),
            subscriptionStore = get(),
            proxySelectionStore = get(),
            overrideStore = get(),
            overrideProfileStore = get(),
            repository = get(),
            bootStartManager = get(),
        )
    }
    single {
        ProfileUpdateScheduler(
            context = androidContext(),
            store = get(),
            scope = get(),
        )
    }
}

package com.clashgo.android.di

import com.clashgo.android.domain.repository.SubscriptionRepository
import com.clashgo.android.data.api.AutoDelayTester
import com.clashgo.android.viewmodel.AppProxyViewModel
import com.clashgo.android.viewmodel.AppUpdateViewModel
import com.clashgo.android.viewmodel.BackupViewModel
import com.clashgo.android.viewmodel.ChainProxyViewModel
import com.clashgo.android.viewmodel.ClashFeaturesViewModel
import com.clashgo.android.viewmodel.RuleOverrideViewModel
import com.clashgo.android.viewmodel.ConnectionViewModel
import com.clashgo.android.viewmodel.DnsQueryViewModel
import com.clashgo.android.viewmodel.HomeViewModel
import com.clashgo.android.viewmodel.LogViewModel
import com.clashgo.android.viewmodel.OverrideProfileViewModel
import com.clashgo.android.viewmodel.ProviderViewModel
import com.clashgo.android.viewmodel.ProxyViewModel
import com.clashgo.android.viewmodel.SubscriptionViewModel
import org.koin.android.ext.koin.androidContext
import org.koin.dsl.module

val viewModelModule = module {
    single { AppUpdateViewModel(get(), get()) }
    single {
        HomeViewModel(
            serviceController = get(),
            overrideStore = get(),
            connectionManager = get(),
            latencyTester = get(),
            getActiveSubscriptionId = { get<SubscriptionRepository>().getActive()?.id },
            activeSubscription = get<SubscriptionRepository>().activeSubscription,
            onLiveProviderInfo = get<SubscriptionRepository>()::setLiveProviderInfo,
        )
    }
    single {
        SubscriptionViewModel(
            repository = get(),
            fileManager = get(),
            processor = get(),
            serviceController = get(),
            context = androidContext(),
        )
    }
    single {
        ProxyViewModel(
            proxySelections = get(),
            getActiveUuid = { get<SubscriptionRepository>().getActive()?.id },
            storage = get(),
            offlineRepository = get(),
            activeSubscriptionId = get<SubscriptionRepository>().currentSubscriptionId,
            autoDelayRuns = get<AutoDelayTester>().completed,
        )
    }
    single {
        AppProxyViewModel(
            storage = get(),
            appListProvider = get(),
            serviceController = get(),
        )
    }
    single { ClashFeaturesViewModel(get()) }
    single { LogViewModel() }
    single { ProviderViewModel() }
    single { ConnectionViewModel() }
    single { DnsQueryViewModel() }
    single {
        OverrideProfileViewModel(
            repository = get(),
            subscriptions = get(),
            serviceController = get(),
        )
    }
    single {
        ChainProxyViewModel(
            repository = get(),
            subscriptions = get(),
            serviceController = get(),
            context = androidContext(),
        )
    }
    single {
        RuleOverrideViewModel(
            repository = get(),
            subscriptions = get(),
            serviceController = get(),
            context = androidContext(),
        )
    }
    single {
        BackupViewModel(
            backupManager = get(),
            storage = get(),
            context = androidContext(),
        )
    }
}

package com.clashgo.android.di

import com.clashgo.android.platform.ProfileFileManager
import com.clashgo.android.service.AndroidProfileFileManager
import org.koin.android.ext.koin.androidContext
import org.koin.dsl.module

val androidAppModule = module {
    single<ProfileFileManager> { AndroidProfileFileManager(androidContext()) }
}

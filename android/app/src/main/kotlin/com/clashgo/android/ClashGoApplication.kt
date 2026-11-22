package com.clashgo.android

import android.app.Application
import android.content.Context
import android.content.res.Configuration
import android.content.pm.ApplicationInfo
import android.os.Build
import com.clashgo.android.data.api.AutoDelayTester
import com.clashgo.android.data.api.MihomoConnectionManager
import com.clashgo.android.data.backup.BackupRestoreRecovery
import com.clashgo.android.data.bridge.RustBackend
import com.clashgo.android.data.bridge.ClashGoCoreBridge
import com.clashgo.android.di.androidAppModule
import com.clashgo.android.di.androidPlatformModule
import com.clashgo.android.di.dataModule
import com.clashgo.android.di.viewModelModule
import com.clashgo.android.domain.model.DelayTestUrl
import com.clashgo.android.platform.PlatformStorage
import com.clashgo.android.platform.ProxyServiceBridge
import com.clashgo.android.platform.StorageKeys
import com.clashgo.android.platform.TunMode
import com.clashgo.android.platform.initToastPlatform
import com.clashgo.android.service.ConfigGenerator
import com.clashgo.android.service.NotificationHelper
import com.clashgo.android.service.ProfileFileOps
import com.clashgo.android.service.ProfileUpdateScheduler
import com.clashgo.android.ui.platform.localizedAppContext
import com.clashgo.android.ui.platform.updateLegacyAppLanguage
import com.clashgo.android.ui.theme.readAppLanguage
import com.clashgo.android.util.AppLogger
import kotlin.concurrent.thread
import org.koin.android.ext.android.inject
import org.koin.android.ext.koin.androidContext
import org.koin.core.context.startKoin
import org.lsposed.hiddenapibypass.HiddenApiBypass

class ClashGoApplication : Application() {

    val connectionManager: MihomoConnectionManager by inject()

    private val updateScheduler: ProfileUpdateScheduler by inject()

    private val autoDelayTester: AutoDelayTester by inject()

    private val storage: PlatformStorage by inject()

    override fun attachBaseContext(base: Context) {
        val language = readAppLanguage(base, PlatformStorage(base))
        super.attachBaseContext(localizedAppContext(base, language))
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            updateLegacyAppLanguage(this, readAppLanguage(this, storage))
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        // 排在最前：后面每一步都要打日志，未初始化时文件写入会静默降级、只剩 logcat。
        AppLogger.initialize(this, PlatformStorage(this).getString(StorageKeys.APP_LOG_LEVEL, AppLogger.DEFAULT_LEVEL))
        // 必须在 Koin 读取订阅/设置之前完成：恢复中断的覆盖操作可能还要把旧目录换回来。
        runCatching { BackupRestoreRecovery.recover(this) }
            .onFailure { AppLogger.error("Application", "Backup restore recovery failed", it) }
        startKoin {
            androidContext(this@ClashGoApplication)
            modules(dataModule, androidPlatformModule, androidAppModule, viewModelModule)
        }
        // 旧版默认地址是 HTTP；升级时写回 HTTPS，避免统一延迟的第二次 HEAD 被 HTTP 劫持后退回首次耗时。
        val storedDelayUrl = storage.getString(StorageKeys.DELAY_TEST_URL, DelayTestUrl.DEFAULT)
        val delayUrl = DelayTestUrl.normalize(storedDelayUrl)
        if (storedDelayUrl != delayUrl) storage.putString(StorageKeys.DELAY_TEST_URL, delayUrl)
        // 必须在任何人读桥之前填：MainActivity 与通知都在 onCreate 之后才起来，这里是唯一
        // 既拿得到设置、又早于全部读取方的位置。
        ProxyServiceBridge.setSelectedTunMode(
            TunMode.fromStorage(storage.getString(StorageKeys.TUN_MODE, TunMode.Vpn.storageValue))
        )
        initToastPlatform(this)
        NotificationHelper.createChannels(this)
        ClashGoCoreBridge.init(homeDir = ProfileFileOps.getGeodataDir(this).absolutePath)
        RustBackend.init(workDir = ConfigGenerator.getWorkDir(this).absolutePath)
        // 解压不能堵住启动；读地理数据的地方各自等 awaitGeodata()。
        thread(name = "geodata-extract") { ProfileFileOps.extractGeodata(this) }
        updateScheduler.start()
        autoDelayTester.start()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val enable = storage.getString(StorageKeys.PREDICTIVE_BACK, "false") == "true"
            HiddenApiBypass.addHiddenApiExemptions("Landroid/content/pm/ApplicationInfo;->setEnableOnBackInvokedCallback")
            setEnableOnBackInvokedCallback(applicationInfo, enable)
        }
    }

    companion object {
        lateinit var instance: ClashGoApplication
            private set

        fun setEnableOnBackInvokedCallback(appInfo: ApplicationInfo, enable: Boolean) {
            runCatching {
                val method = ApplicationInfo::class.java.getDeclaredMethod(
                    "setEnableOnBackInvokedCallback",
                    Boolean::class.javaPrimitiveType,
                )
                method.isAccessible = true
                method.invoke(appInfo, enable)
            }
        }
    }
}

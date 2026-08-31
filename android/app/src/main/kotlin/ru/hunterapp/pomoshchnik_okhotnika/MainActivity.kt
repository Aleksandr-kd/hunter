package ru.hunterapp.pomoshchnik_okhotnika

import android.app.Activity
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import ru.rustore.sdk.appupdate.listener.InstallStateUpdateListener
import ru.rustore.sdk.appupdate.manager.RuStoreAppUpdateManager
import ru.rustore.sdk.appupdate.manager.factory.RuStoreAppUpdateManagerFactory
import ru.rustore.sdk.appupdate.model.AppUpdateOptions
import ru.rustore.sdk.appupdate.model.AppUpdateType
import ru.rustore.sdk.appupdate.model.InstallStatus
import ru.rustore.sdk.appupdate.model.UpdateAvailability

class MainActivity : FlutterFragmentActivity() {

    private val TAG = "RuStoreAppUpdate"
    private val CHANNEL = "ru.hunterapp/app_update"

    private var updateManager: RuStoreAppUpdateManager? = null
    private var installStateListener: InstallStateUpdateListener? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        updateManager = RuStoreAppUpdateManagerFactory.create(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkForFlexibleUpdate" -> checkForFlexibleUpdate(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun checkForFlexibleUpdate(result: MethodChannel.Result) {
        val manager = updateManager ?: run {
            result.error("MANAGER_NULL", "App update manager not initialized", null)
            return
        }

        manager
            .getAppUpdateInfo()
            .addOnSuccessListener { appUpdateInfo ->
                when {
                    appUpdateInfo.updateAvailability == UpdateAvailability.UPDATE_AVAILABLE -> {
                        // Регистрируем слушатель статуса скачивания и запускаем отложенное обновление.
                        registerDownloadListener(result)
                        val options = AppUpdateOptions.Builder().build() // FLEXIBLE по умолчанию
                        manager
                            .startUpdateFlow(appUpdateInfo, options)
                            .addOnSuccessListener { resultCode ->
                                Log.i(TAG, "startUpdateFlow resultCode=$resultCode")
                                if (resultCode == Activity.RESULT_CANCELED) {
                                    // Пользователь отказался от скачивания.
                                    // Листенер держим для повторного запуска обновления.
                                }
                            }
                            .addOnFailureListener { throwable ->
                                Log.e(TAG, "startUpdateFlow error", throwable)
                                unregisterListener()
                                result.error("START_FAILED", throwable.message, throwable.toString())
                            }
                    }
                    appUpdateInfo.updateAvailability == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS &&
                        appUpdateInfo.installStatus == InstallStatus.DOWNLOADED -> {
                        // Обновление уже скачано, но не установлено — завершаем установку.
                        completeFlexibleUpdate(result)
                    }
                    else -> {
                        Log.i(
                            TAG,
                            "No update available, availability=${appUpdateInfo.updateAvailability}, " +
                                "installStatus=${appUpdateInfo.installStatus}"
                        )
                        result.success(
                            mapOf(
                                "available" to false,
                                "updateAvailability" to appUpdateInfo.updateAvailability,
                                "installStatus" to appUpdateInfo.installStatus
                            )
                        )
                    }
                }
            }
            .addOnFailureListener { throwable ->
                Log.e(TAG, "getAppUpdateInfo error", throwable)
                result.error("CHECK_FAILED", throwable.message, throwable.toString())
            }
    }

    private fun registerDownloadListener(result: MethodChannel.Result) {
        installStateListener = InstallStateUpdateListener { installState ->
            when (installState.installStatus) {
                InstallStatus.DOWNLOADED -> {
                    Log.i(TAG, "Update downloaded, completing flexible update")
                    completeFlexibleUpdate(result)
                }
                InstallStatus.DOWNLOADING -> {
                    Log.i(
                        TAG,
                        "Downloading: ${installState.bytesDownloaded}/${installState.totalBytesToDownload}"
                    )
                }
                InstallStatus.FAILED -> {
                    Log.e(TAG, "Download failed, errorCode=${installState.installErrorCode}")
                    unregisterListener()
                    result.error(
                        "DOWNLOAD_FAILED",
                        "Failed to download update",
                        installState.installErrorCode
                    )
                }
                else -> Log.d(TAG, "Install status: ${installState.installStatus}")
            }
        }
        updateManager?.registerListener(installStateListener!!)
    }

    private fun completeFlexibleUpdate(result: MethodChannel.Result) {
        val manager = updateManager ?: return
        val options = AppUpdateOptions.Builder().appUpdateType(AppUpdateType.FLEXIBLE).build()
        manager
            .completeUpdate(options)
            .addOnFailureListener { throwable ->
                Log.e(TAG, "completeUpdate error", throwable)
                result.error("COMPLETE_FAILED", "Failed to install update", throwable.toString())
            }
    }

    private fun unregisterListener() {
        installStateListener?.let { listener -> updateManager?.unregisterListener(listener) }
        installStateListener = null
    }

    override fun onDestroy() {
        unregisterListener()
        super.onDestroy()
    }
}

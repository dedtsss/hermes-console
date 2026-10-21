package com.hermesagent.hermes_android

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors
import java.util.zip.ZipFile

class HermesAppUpdateFileProvider : FileProvider()

// Only the fork's direct/full manifest grants REQUEST_INSTALL_PACKAGES.
// No caller-supplied path, URI, package or Intent is accepted by this channel.
class HermesAppUpdateHandler(private val activity: Activity) :
    MethodChannel.MethodCallHandler, AutoCloseable {
    companion object {
        const val CHANNEL = "hermes/app_update"
        const val INSTALL_REQUEST = 4761
        private const val PACKAGE = "io.github.dedtsss.hermesconsole"
        private const val INSTALL_PERMISSION = "android.permission.REQUEST_INSTALL_PACKAGES"
    }

    private val executor = Executors.newSingleThreadExecutor()
    private var apk = File(activity.cacheDir, "app_update/update.apk")
    private var validating = false
    private var pendingInstall: MethodChannel.Result? = null
    @Volatile private var closed = false

    @Suppress("DEPRECATION")
    private fun ownInfo(): PackageInfo =
        activity.packageManager.getPackageInfo(activity.packageName, PackageManager.GET_PERMISSIONS)

    private fun supported(): Boolean =
        activity.packageName == PACKAGE &&
            Build.SUPPORTED_ABIS.contains("arm64-v8a") &&
            ownInfo().requestedPermissions?.contains(INSTALL_PERMISSION) == true

    @Suppress("DEPRECATION")
    private fun code(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (closed) { result.error("cancelled", null, null); return }
        try {
            if (call.method == "getInfo") {
                val info = ownInfo()
                result.success(mapOf(
                    "supported" to supported(),
                    "versionName" to info.versionName,
                    "versionCode" to code(info),
                ))
                return
            }
            check(supported())
            when (call.method) {
                "prepareDownload" -> {
                    check(pendingInstall == null && !validating)
                    apk.parentFile!!.mkdirs()
                    apk.parentFile!!.listFiles()?.forEach { it.delete() }
                    // A cancelled Dart download can only remove its own old file.
                    apk = File(apk.parentFile, "${UUID.randomUUID()}.apk")
                    result.success(apk.absolutePath)
                }
                "openSources" -> {
                    if (Build.VERSION.SDK_INT >= 26) {
                        activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:${activity.packageName}")))
                    }
                    result.success(null)
                }
                "validate", "install" -> {
                    check(pendingInstall == null && !validating)
                    validating = true
                    executor.execute {
                        try {
                            validate(call)
                            activity.runOnUiThread {
                                validating = false
                                if (closed) return@runOnUiThread
                                try {
                                    if (call.method == "validate") result.success(null)
                                    else launchInstaller(result)
                                } catch (_: Exception) {
                                    pendingInstall = null
                                    result.error("installer", null, null)
                                }
                            }
                        } catch (_: Exception) {
                            activity.runOnUiThread {
                                validating = false
                                if (!closed) result.error("invalid_apk", null, null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("unavailable", null, null)
        }
    }

    @Suppress("DEPRECATION")
    private fun validate(call: MethodCall) {
        val expectedCode = call.argument<Number>("versionCode")?.toLong() ?: error("version")
        val expectedName = call.argument<String>("versionName") ?: error("version")
        val expectedHash = call.argument<String>("sha256") ?: error("digest")
        check(Regex("[0-9a-f]{64}").matches(expectedHash))
        check(apk.isFile && apk.length() in 1..(512L * 1024 * 1024))
        val digest = MessageDigest.getInstance("SHA-256")
        apk.inputStream().use { input ->
            val buffer = ByteArray(128 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                check(!closed)
                digest.update(buffer, 0, count)
            }
        }
        check(digest.digest().joinToString("") { "%02x".format(it) } == expectedHash)
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES
                    else PackageManager.GET_SIGNATURES
        val archive = activity.packageManager.getPackageArchiveInfo(apk.absolutePath, flags)
            ?: error("archive")
        check(archive.packageName == PACKAGE && archive.packageName == activity.packageName)
        check(code(archive) == expectedCode && expectedCode > code(ownInfo()))
        check(archive.versionName == expectedName)
        check(archive.applicationInfo?.flags?.and(ApplicationInfo.FLAG_DEBUGGABLE) == 0)
        val signed = if (Build.VERSION.SDK_INT >= 28)
            archive.signingInfo?.apkContentsSigners?.isNotEmpty() == true
            else archive.signatures?.isNotEmpty() == true
        check(signed)
        ZipFile(apk).use { zip ->
            check(zip.getEntry("lib/arm64-v8a/libflutter.so") != null)
            check(zip.getEntry("lib/arm64-v8a/libapp.so") != null)
        }
    }

    @Suppress("DEPRECATION")
    private fun launchInstaller(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
            result.success("permission_required")
            return
        }
        val uri = FileProvider.getUriForFile(activity,
            "${activity.packageName}.app_update_provider", apk)
        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            clipData = ClipData.newRawUri("APK", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            putExtra(Intent.EXTRA_RETURN_RESULT, true)
        }
        pendingInstall = result
        activity.startActivityForResult(intent, INSTALL_REQUEST)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != INSTALL_REQUEST) return false
        val pending = pendingInstall
        pendingInstall = null
        pending?.success(if (resultCode == Activity.RESULT_OK) "installed" else "cancelled")
        return true
    }

    override fun close() {
        closed = true
        pendingInstall?.error("cancelled", null, null)
        pendingInstall = null
        executor.shutdownNow()
    }
}

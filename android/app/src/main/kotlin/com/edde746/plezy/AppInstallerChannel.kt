package com.edde746.plezy

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Installs a downloaded update APK via [PackageInstaller]'s session API,
 * skipping the browser/Downloader-app detour: Dart streams the APK to
 * app-private storage (see UpdateService.downloadAndInstallAndroidUpdate),
 * hands this channel the local path, and this opens a session, copies the
 * file into it, and commits. Android answers with STATUS_PENDING_USER_ACTION
 * on commit (a session can be committed from a background context that has
 * no Activity to show the confirmation UI from), which arrives here as a
 * broadcast carrying an Intent to start — that's the system's normal
 * "Install this app?" screen, launched directly rather than through
 * Downloader/a browser.
 *
 * The Dart-side caller deletes its own copy of the APK as soon as this
 * channel's `install` call returns: by then PackageInstaller has already
 * streamed the bytes into its own session storage, so nothing is lost by
 * cleaning up immediately regardless of what the user does with the
 * confirmation screen afterward.
 */
internal class AppInstallerChannel(private val activity: Activity) {
  companion object {
    private const val CHANNEL = "com.plezy/app_installer"
    private const val INSTALL_STATUS_ACTION = "com.edde746.plezy.INSTALL_STATUS"
    private const val SESSION_NAME = "plezy_update"
  }

  private var statusReceiver: BroadcastReceiver? = null

  fun attach(messenger: BinaryMessenger) {
    MethodChannel(messenger, CHANNEL).setMethodCallHandler(::onMethodCall)
    registerStatusReceiver()
  }

  fun dispose() {
    statusReceiver?.let {
      try {
        activity.unregisterReceiver(it)
      } catch (_: IllegalArgumentException) {
        // Already unregistered (or never successfully registered) - nothing to undo.
      }
    }
    statusReceiver = null
  }

  private fun registerStatusReceiver() {
    if (statusReceiver != null) return
    val receiver = object : BroadcastReceiver() {
      override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        if (status != PackageInstaller.STATUS_PENDING_USER_ACTION) {
          // Terminal statuses (STATUS_SUCCESS / STATUS_FAILURE*) need no
          // action here - see the class doc on why cleanup doesn't wait
          // for this.
          return
        }
        val confirmIntent = extractConfirmIntent(intent) ?: return
        confirmIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
          activity.startActivity(confirmIntent)
        } catch (_: Exception) {
          // Nothing sensible to do if the system installer UI can't launch.
        }
      }
    }
    val filter = IntentFilter(INSTALL_STATUS_ACTION)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      activity.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
    } else {
      @Suppress("UnspecifiedRegisterReceiverFlag")
      activity.registerReceiver(receiver, filter)
    }
    statusReceiver = receiver
  }

  @Suppress("DEPRECATION")
  private fun extractConfirmIntent(intent: Intent): Intent? =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
    } else {
      intent.getParcelableExtra(Intent.EXTRA_INTENT)
    }

  private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    if (call.method != "install") {
      result.notImplemented()
      return
    }

    val filePath = call.argument<String>("filePath")
    if (filePath == null) {
      result.error("INVALID_ARGUMENT", "filePath is required", null)
      return
    }
    val file = File(filePath)
    if (!file.exists()) {
      result.error("FILE_NOT_FOUND", "Downloaded update file is missing", null)
      return
    }

    try {
      commitInstallSession(file)
      result.success(true)
    } catch (error: Exception) {
      result.error("INSTALL_FAILED", error.message ?: error.javaClass.simpleName, null)
    }
  }

  private fun commitInstallSession(file: File) {
    val packageInstaller = activity.packageManager.packageInstaller
    val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
    val sessionId = packageInstaller.createSession(params)
    val session = packageInstaller.openSession(sessionId)
    session.use {
      it.openWrite(SESSION_NAME, 0, file.length()).use { out ->
        file.inputStream().use { input -> input.copyTo(out) }
        it.fsync(out)
      }
      val statusIntent = Intent(INSTALL_STATUS_ACTION).setPackage(activity.packageName)
      val flags = PendingIntent.FLAG_UPDATE_CURRENT or
        (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_MUTABLE else 0)
      val pendingIntent = PendingIntent.getBroadcast(activity, sessionId, statusIntent, flags)
      it.commit(pendingIntent.intentSender)
    }
  }
}

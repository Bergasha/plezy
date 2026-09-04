package com.edde746.plezy.watchnext

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.WorkManager
import com.edde746.plezy.MainActivity
import com.edde746.plezy.R
import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Reopens the app and migrates versioned shelf state after an update, and
 * restores volatile launcher grants after boot.
 */
class SystemShelfUpdateReceiver private constructor(
  private val executor: Executor,
  private val ownsExecutor: Boolean
) : BroadcastReceiver() {
  constructor() : this(Executors.newSingleThreadExecutor(), true)
  internal constructor(executor: Executor) : this(executor, false)

  companion object {
    private const val TAG = "SystemShelfUpdateReceiver"

    /**
     * Unique name of the periodic ShelfRefreshWorker job 2.13.0 shipped and
     * enqueued (KEEP, persisted by WorkManager). The worker is gone, so on an
     * updated device the persisted job would wake the process once more, fail
     * to instantiate the deleted class, and linger as a permanently failed
     * record; cancel it on the first update instead.
     */
    internal const val LEGACY_SHELF_REFRESH_WORK = "plezy_shelf_refresh"

    private const val RELAUNCH_CHANNEL_ID = "plezy_relaunch"
    private const val RELAUNCH_NOTIFICATION_ID = 4201
  }

  override fun onReceive(context: Context, intent: Intent) {
    val action = intent.action
    if (action != Intent.ACTION_MY_PACKAGE_REPLACED && action != Intent.ACTION_BOOT_COMPLETED) return

    // Reopen right where we left off - PackageInstaller kills the running
    // process to apply the update, so without this the user is dropped on
    // whatever screen they were on (home, another app) once it's done.
    // Never fires for a fresh install (only a replace of an already-installed
    // build), so this only ever fires when the user was already in the app
    // triggering it via our in-app updater.
    if (action == Intent.ACTION_MY_PACKAGE_REPLACED) {
      relaunchApp(context)
    }

    val pending = goAsync()
    executor.execute {
      try {
        val provider = WatchNextProvider.forMaintenance(context.applicationContext)
        if (action == Intent.ACTION_MY_PACKAGE_REPLACED) {
          cancelLegacyShelfRefreshWork(context.applicationContext)
          provider.migrateShelfSchema()
        } else {
          provider.restoreReadGrants()
        }
      } finally {
        pending?.finish()
        if (ownsExecutor) (executor as ExecutorService).shutdown()
      }
    }
  }

  /**
   * A plain `startActivity` here is unreliable across OEMs: Android's
   * background-activity-start allowance for MY_PACKAGE_REPLACED is
   * documented but enforced inconsistently (Shield's Android TV build
   * silently swallows it - the exception is caught and logged, nothing
   * crashes, the app just never comes back). A full-screen-intent
   * notification is the mechanism Android actually guarantees for exactly
   * this "bring the app to the foreground from the background" case (it's
   * how alarm/call apps reliably take over the screen); the OS launches it
   * directly when it judges that safe, and otherwise falls back to a normal
   * tap-to-open notification - so this can never do *nothing*, only
   * degrade from automatic to one tap.
   */
  private fun relaunchApp(context: Context) {
    try {
      ensureRelaunchChannel(context)

      val launchIntent = Intent(context, MainActivity::class.java).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
      }
      val pendingIntent = PendingIntent.getActivity(
        context,
        RELAUNCH_NOTIFICATION_ID,
        launchIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
      )

      val notification = NotificationCompat.Builder(context, RELAUNCH_CHANNEL_ID)
        .setSmallIcon(R.drawable.ic_stat_notification)
        .setContentTitle("Plezy")
        .setContentText("Update installed - tap to reopen")
        .setPriority(NotificationCompat.PRIORITY_HIGH)
        .setCategory(NotificationCompat.CATEGORY_REMINDER)
        .setContentIntent(pendingIntent)
        .setFullScreenIntent(pendingIntent, true)
        .setAutoCancel(true)
        .setOngoing(false)
        .build()

      NotificationManagerCompat.from(context).notify(RELAUNCH_NOTIFICATION_ID, notification)
    } catch (e: Exception) {
      Log.e(TAG, "Failed to relaunch after update", e)
    }
  }

  private fun ensureRelaunchChannel(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    if (manager.getNotificationChannel(RELAUNCH_CHANNEL_ID) != null) return
    val channel = NotificationChannel(
      RELAUNCH_CHANNEL_ID,
      "App updates",
      NotificationManager.IMPORTANCE_HIGH
    ).apply {
      description = "Lets Plezy reopen itself after installing an update"
    }
    manager.createNotificationChannel(channel)
  }

  /** Best-effort by design: shelf maintenance must not die on a WorkManager failure. */
  private fun cancelLegacyShelfRefreshWork(context: Context) {
    try {
      WorkManager.getInstance(context).cancelUniqueWork(LEGACY_SHELF_REFRESH_WORK)
    } catch (e: Exception) {
      Log.e(TAG, "Failed to cancel legacy shelf refresh work", e)
    }
  }
}

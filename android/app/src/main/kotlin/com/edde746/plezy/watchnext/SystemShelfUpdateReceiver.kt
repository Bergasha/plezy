package com.edde746.plezy.watchnext

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.work.WorkManager
import com.edde746.plezy.MainActivity
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
  }

  override fun onReceive(context: Context, intent: Intent) {
    val action = intent.action
    if (action != Intent.ACTION_MY_PACKAGE_REPLACED && action != Intent.ACTION_BOOT_COMPLETED) return

    // Reopen right where we left off - PackageInstaller kills the running
    // process to apply the update, so without this the user is dropped on
    // whatever screen they were on (home, another app) once it's done.
    // Must happen synchronously here, before any async work below: Android's
    // background-activity-start exemption for this broadcast only covers the
    // duration of onReceive itself, not work continued after goAsync().
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

  /** Best-effort: a failed relaunch just leaves the user where the install left them. */
  private fun relaunchApp(context: Context) {
    try {
      val launchIntent = Intent(context, MainActivity::class.java).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
      }
      context.startActivity(launchIntent)
    } catch (e: Exception) {
      Log.e(TAG, "Failed to relaunch after update", e)
    }
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

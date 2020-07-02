package org.fitrecord.android.service

import android.app.PendingIntent
import android.app.PendingIntent.FLAG_UPDATE_CURRENT
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationCompat.Builder
import org.fitrecord.android.R

private const val REQUEST_ACTION = 2

class ActionReceiver : BroadcastReceiver() {

    private val recordingService = ConnectableServiceConnection<RecordingService>()
    
    override fun onReceive(context: Context?, intent: Intent?) {
        recordingService.start(context!!, RecordingService::class.java) {
            it.data = intent?.data
            Unit
        }
    }

}

enum class ActionType(val icon: Int) {
    Cancel(R.drawable.ic_notification_ready), Record(R.drawable.ic_notification_record), Pause(R.drawable.ic_notification_pause), Lap(R.drawable.ic_notification_record)
}

fun makeActionIntent(ctx: Context, action: ActionType): PendingIntent {
    val intent = Intent(ctx, ActionReceiver::class.java).apply { 
        data = Uri.fromParts("fitrecord", "action", action.toString())
    }
    return PendingIntent.getBroadcast(ctx, REQUEST_ACTION, intent, FLAG_UPDATE_CURRENT)
}

fun addNotificationAction(ctx: Context, builder: Builder, action: ActionType, text: String): Builder {
    return builder.addAction(action.icon, text, makeActionIntent(ctx, action))
}

fun parseActionType(uri: Uri?): ActionType? {
    if (uri?.schemeSpecificPart != "action") return null
    try {
        return ActionType.valueOf(uri?.fragment ?: "?")
    } catch (t: Throwable) {
        Log.e("Action", "Invalid Intent: $uri")
    }
    return null
}
    

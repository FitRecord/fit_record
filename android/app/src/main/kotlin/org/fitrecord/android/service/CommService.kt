package org.fitrecord.android.service

import android.content.Intent
import android.content.Intent.FLAG_ACTIVITY_NEW_TASK
import android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION
import android.content.pm.PackageManager
import android.content.pm.PackageManager.MATCH_DEFAULT_ONLY
import android.content.pm.ResolveInfo
import android.util.Log
import androidx.core.app.ShareCompat
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import org.fitrecord.android.MainActivity
import java.io.File

class CommService : ConnectableService() {

    fun export(activity: MainActivity, channel: MethodChannel?, call: Result, id: Int, type: String) {
        val handler = object : Result {
            override fun notImplemented() {
                Log.w("Comm", "Not implemented")
                call.error("Not implemented", null, null)
            }

            override fun error(errorCode: String?, errorMessage: String?, errorDetails: Any?) {
                Log.e("Comm", "Error $errorCode $errorMessage")
                call.error(errorCode, errorMessage, errorDetails)
            }

            override fun success(result: Any?) {
                if (result == null) {
                    return call.error("Invalid result", null, null);
                }
                val map = result as Map<String, String?>
                if (shareFile(activity, map["file"], map["content_type"])) {
                    call.success(map["file"])
                } else {
                    call.success(null)
                }
            }
        }
        channel?.invokeMethod("export", mapOf("id" to id, "type" to type, "dir" to cacheDir.absolutePath), handler)
    }

    private fun shareFile(activity: MainActivity, file: String?, type: String?): Boolean {
        try {
            val uri = FileProvider.getUriForFile(activity, "org.fitrecord.android.export", File(file))
            val intent = ShareCompat.IntentBuilder.from(activity)
                    .setType(type)
                    .setStream(uri)
                    .setChooserTitle("FitRecord export")
                    .createChooserIntent()
                    .addFlags(FLAG_ACTIVITY_NEW_TASK or FLAG_GRANT_READ_URI_PERMISSION)
            val resInfoList: List<ResolveInfo> = packageManager.queryIntentActivities(intent, MATCH_DEFAULT_ONLY)
            resInfoList.forEach {
                activity.grantUriPermission(it.activityInfo.packageName, uri, FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivity(intent)
            return true
        } catch (t: Exception) {
            Log.e("Comm", "Share error:", t)
        }
        return false
    }
}
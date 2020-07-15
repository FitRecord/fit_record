package org.fitrecord.android.service

import android.content.Intent
import android.content.Intent.FLAG_ACTIVITY_NEW_TASK
import android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION
import android.content.pm.PackageManager
import android.content.pm.PackageManager.MATCH_DEFAULT_ONLY
import android.content.pm.ResolveInfo
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.ShareCompat
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import org.fitrecord.android.MainActivity
import java.io.File
import java.io.FileDescriptor
import java.io.FileInputStream
import java.io.FileOutputStream

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

    fun importStart(activity: MainActivity, code: Int) {
        try {
            val requestIntent = Intent(Intent.ACTION_GET_CONTENT).apply {
                type = "*/*"
            }
            activity.startActivityForResult(Intent.createChooser(requestIntent, "TCX file import"), code)
        } catch (e: Exception) {
            Log.e("Comm", "Failed to start import", e)
        }
    }

    fun importComplete(intent: Intent?, callback: (String) -> Unit) {
        intent?.data?.let { uri ->
            try {
                contentResolver.openFileDescriptor(uri, "r")
            } catch (e: Exception) {
                Log.e("Comm", "Error importing file", e)
                return
            }?.let { fd ->
                try {
                    val outFile = File.createTempFile("fit_record_", ".xml")
                    FileInputStream(fd.fileDescriptor).use { w ->
                        FileOutputStream(outFile).use { f -> w.copyTo(f) }
                        callback(outFile.absolutePath)
                    }
                } catch (e: Exception) {
                    Log.e("Comm", "Error copying file", e)
                }
            }
        }
    }
}
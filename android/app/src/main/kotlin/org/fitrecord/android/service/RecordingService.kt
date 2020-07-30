package org.fitrecord.android.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationCompat.Builder
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.FlutterCallbackInformation
import io.flutter.view.FlutterMain
import org.fitrecord.android.MainActivity
import org.fitrecord.android.R
import org.fitrecord.android.sensor.SensorRegistry
import org.fitrecord.android.service.ActionType.*
import java.util.*

interface RecordingListener {
    fun onStatusChanged()
    fun onSensorData(data: Map<String, Double>)
    fun onSensorStatus(data: List<Map<String, Int?>>)
    fun onHistoryUpdated(record: Int?);
}

class RecordingService : ConnectableService() {

    private val OPEN_MAIN = 1
    private val IDLE_AUTO_OFF = 60 * 5;
    val listeners = Listeners<RecordingListener>()

    private var wl: PowerManager.WakeLock? = null
    private var selectedProfile: Int? = null
    private var idleCount: Int = 0
    private val BACKGROUND_CHANNEL = "org.fitrecord/background"
    internal var backgroundChannel: MethodChannel? = null

    private var engine: FlutterEngine? = null
    private val FOREGROUND_NOTIFICATION = 1
    private var sensors: SensorRegistry? = null
    private var sensorTimer: Timer? = null

    override fun onCreate() {
        super.onCreate()
        Log.i("Recording", "Service created")
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wl = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "fitrecord:Recording").also {
            it.setReferenceCounted(false)
        }
    }

    override fun onDestroy() {
        Log.i("Recording", "Service destroyed")
        engine?.let {
            it.destroy();
            engine = null
        }
        deactivate()
        super.onDestroy()
    }

    internal fun initFlutter(callbackID: Long, callback: (engine: FlutterEngine) -> Unit) {
        mainHandler.post {
            if (engine == null) {
                engine = FlutterEngine(this).apply {
                    val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(callbackID)
                    backgroundChannel = MethodChannel(dartExecutor.binaryMessenger, BACKGROUND_CHANNEL).apply {
                        setMethodCallHandler { call, result ->
                            when (call.method) {
                                "initialized" -> {
                                    callback(engine!!)
                                    result.success(null)
                                }
                                else -> handleBackgroundChannel(call, result)
                            }
                        }
                    }
                    dartExecutor.executeDartCallback(DartExecutor.DartCallback(assets, FlutterMain.findAppBundlePath(), callbackInfo))
                }
            } else callback(engine!!)
        }
    }

    private fun handleBackgroundChannel(call: MethodCall, result: Result) {
        Log.i("Recording", "backgroundChannel call ${call.method}")
        when (call.method) {
            "activate" -> {
                val args = call.arguments as Map<String, Any>
                activate(args.get("profile_id") as Int)
                result.success(0)
            }
            else -> result.notImplemented()
        }
    }

    private fun ensureNotificationChannel(id: String, name: String, description: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(id, name, NotificationManager.IMPORTANCE_DEFAULT)
            channel.description = description;
            NotificationManagerCompat.from(this).createNotificationChannel(channel);
        }
    }

    fun activate(profileId: Int) {
        synchronized(BACKGROUND_CHANNEL) {
            if (sensors != null) return // Already started
            idleCount = 0
            wl?.acquire()
            sensors = SensorRegistry()
            backgroundChannel?.invokeMethod("profileInfo", profileId, makeSimpleResult<Map<String, Any>>("profileInfo") {
                it?.let { args: Map<String, Any> ->
                    sensors?.init(this@RecordingService, args["sensors"] as List<Map<String, Any>>)
                    sensorTimer = Timer("Sensor").also {
                        it.scheduleAtFixedRate(object : TimerTask() {

                            override fun run() {
                                querySensors()
                            }
                        }, 1000L, 1000L)
                    }
                    Unit
                }
            })
        }
        selectedProfile = profileId
        val n = updateWithStatus(null, "FitRecord")
        startForeground(FOREGROUND_NOTIFICATION, n)
    }

    private fun updateWithStatus(status: Int?, text: String): Notification {
        when (status) {
            0 -> {
                return updateNotification("Recording", text, R.drawable.ic_notification_record) {
                    addNotificationAction(this, it, Pause, "Pause")
                }
            }
            1 -> {
                return updateNotification("Paused", text, R.drawable.ic_notification_pause) {
                    addNotificationAction(this, it, Record, "Resume")
                }
            }
        }
        return updateNotification("Ready", text, R.drawable.ic_notification_ready) {
            addNotificationAction(this, it, Record, "Start")
            addNotificationAction(this, it, Cancel, "Cancel")
        }
    }

    private fun updateNotification(title: String, text: String, icon: Int, callback: (Builder) -> Builder): Notification {
        ensureNotificationChannel("foreground", "Recording notification", "Recording notification")
        val activityIntent = Intent(this, MainActivity::class.java)
        val intent = PendingIntent.getActivity(this, OPEN_MAIN, activityIntent, PendingIntent.FLAG_UPDATE_CURRENT)
        val builder = Builder(this, "foreground")
                .setContentTitle(title)
                .setContentText(text)
                .setOngoing(true)
                .setDefaults(0)
                .setContentIntent(intent)
                .setSmallIcon(icon)
                .setOnlyAlertOnce(true)
        val n = callback(builder).build()
        NotificationManagerCompat.from(this).apply {
            notify(FOREGROUND_NOTIFICATION, n)
        }
        return n
    }

    private fun querySensors() {
        sensors?.collectData().let {
            mainHandler.post {
                backgroundChannel?.invokeMethod("sensorsData", it, makeSimpleResult<Map<String, Any>>("sensorsData") {
                    it?.let { data: Map<String, Any> ->
                        listeners.invoke {
                            val sensors = data["data"] as Map<String, Double>?
                            sensors?.let { sensors ->
                                it.onSensorData(sensors)
                                val status = (sensors["status"] as Double?)?.toInt()
                                if (status == null) {
                                    idleCount++
                                    if (idleCount >= IDLE_AUTO_OFF) {
                                        deactivate()
                                    }
                                } else idleCount = 0
                                val statusText = data["status_text"] as String?
                                statusText?.let { updateWithStatus(status, it) }
                            }
                            it.onSensorStatus(data["status"] as List<Map<String, Int?>>)
                        }
                    }

                })
            }
        }
    }

    fun deactivate() {
        stopForeground(true)
        synchronized(BACKGROUND_CHANNEL) {
            sensorTimer?.let {
                it.cancel()
                sensorTimer = null
            }
            sensors?.let {
                it.destroy(this)
                sensors = null
            }
            wl?.release()
            listeners.invoke {
                it.onStatusChanged()
            }
        }
    }

    fun activated(): Boolean {
        synchronized(BACKGROUND_CHANNEL) {
            return sensors != null
        }
    }

    fun start(delay: Int) {
        backgroundChannel?.invokeMethod("start", mapOf("profile_id" to selectedProfile), makeSimpleResult<Any>("start") {
            listeners.invoke { it.onStatusChanged() }
            querySensors()
        })
    }

    fun pause() {
        backgroundChannel?.invokeMethod("pause", null, makeSimpleResult<Any>("pause") {
            listeners.invoke { it.onStatusChanged() }
            querySensors()
        })
    }

    fun lap() {
        backgroundChannel?.invokeMethod("lap", null, makeSimpleResult<Any>("lap") {
            listeners.invoke { it.onStatusChanged() }
            querySensors()
        })
    }

    fun finish(save: Boolean, callback: (Int?) -> Unit) {
        backgroundChannel?.invokeMethod("finish", mapOf("save" to save), makeSimpleResult<Int>("finish") {
            listeners.invoke { it.onStatusChanged() }
            querySensors()
            callback(it)
        })
    }

    override fun onIntent(intent: Intent, uri: Uri?) {
        parseActionType(uri)?.let { action ->
            Log.d("Recording", "Action: $action")
            when (action) {
                Record -> start(0)
                Pause -> pause()
                Lap -> lap()
                Cancel -> deactivate()
            }
        }
    }

    fun importFile(): (String) -> Unit {
        return {
            backgroundChannel?.invokeMethod("import", mapOf("file" to it), makeSimpleResult<Int>("import") { id ->
                listeners.invoke { it.onHistoryUpdated(id) }
            })
        }
    }

}

@Suppress("UNCHECKED_CAST")
fun <T> makeSimpleResult(name: String, callback: (T?) -> Unit?): Result {
    return object : Result {
        override fun notImplemented() {
            Log.w("Recording", "Not implemented: $name")
        }

        override fun error(errorCode: String?, errorMessage: String?, errorDetails: Any?) {
            Log.e("Recording", "Error: $errorCode, $errorMessage, $errorDetails")
        }

        override fun success(result: Any?) {
            callback(result as T?)
        }

    }
}
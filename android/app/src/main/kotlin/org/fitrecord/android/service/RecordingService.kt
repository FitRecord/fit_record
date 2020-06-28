package org.fitrecord.android.service

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
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
import java.util.*

interface RecordingListener {
    fun onStatusChanged()
    fun onSensorData(data: Map<String, Double>)
    fun onSensorStatus(data: List<Map<String, Int?>>)
}

class RecordingService : ConnectableService() {

    private val OPEN_MAIN = 1
    private val IDLE_AUTO_OFF = 60 * 5;
    val listeners = Listeners<RecordingListener>()

    var callbackID: Long? = null
        set(value) {
            field = value
            value?.let { mainHandler.post { initFlutter(it) } }
        }
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

    private fun initFlutter(callbackID: Long) {
        if (engine == null) {
            engine = FlutterEngine(this).apply {
                val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(callbackID)
                Log.d("Recording", "Callback: ${callbackInfo.callbackClassName}, ${callbackInfo.callbackName}")
                dartExecutor.executeDartCallback(DartExecutor.DartCallback(assets, FlutterMain.findAppBundlePath(), callbackInfo))
                backgroundChannel = MethodChannel(dartExecutor.binaryMessenger, BACKGROUND_CHANNEL).apply {
                    setMethodCallHandler { call, result -> handleBackgroundChannel(call, result) }
                }
            }
        }
    }

    private fun handleBackgroundChannel(call: MethodCall, result: Result) {
        Log.i("Recording", "backgroundChannel call ${call.method}")
        when (call.method) {
            "activate" -> {
                val args = call.arguments as Map<String, Object>
                activate(args.get("profile_id") as Int)
                result.success(0)
            }
        }
        result.success(null)
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
            val handler = object : Result {
                override fun notImplemented() {
                    Log.e("Recording", "No profileInfo")
                }

                override fun error(errorCode: String?, errorMessage: String?, errorDetails: Any?) {
                    Log.e("Recording", "Error: $errorCode, $errorMessage")
                }

                override fun success(result: Any?) {
                    val args = result as Map<String, Any>
                    sensors?.init(this@RecordingService, args["sensors"] as List<Map<String, Any>>)
                    sensorTimer = Timer("Sensor").also {
                        it.scheduleAtFixedRate(object : TimerTask() {

                            override fun run() {
                                querySensors()
                            }
                        }, 1000L, 1000L)
                    }
                }

            }
            backgroundChannel?.invokeMethod("profileInfo", profileId, handler)
        }
        selectedProfile = profileId
        ensureNotificationChannel("foreground", "Recording notification", "Recording notification")
        val activityIntent = Intent(this, MainActivity::class.java)
        val intent = PendingIntent.getActivity(this, OPEN_MAIN, activityIntent, PendingIntent.FLAG_UPDATE_CURRENT)
        val n = NotificationCompat.Builder(this, "foreground")
                .setContentTitle("FitRecord")
                .setContentText("FitRecord is getting ready")
                .setOngoing(true)
                .setDefaults(0)
                .setContentIntent(intent)
                .setSmallIcon(R.drawable.ic_notification_record)
                .build()
        startForeground(FOREGROUND_NOTIFICATION, n)
    }

    private fun querySensors() {
//        Log.i("Recording", "Time to query sensors")
        sensors?.collectData().let {
            val handler = object : Result {
                override fun notImplemented() {
                    TODO("Not yet implemented")
                }

                override fun error(errorCode: String?, errorMessage: String?, errorDetails: Any?) {
                    Log.e("Recording", "sensorsData $errorCode, $errorMessage, $errorDetails")
                }

                override fun success(result: Any?) {
                    result?.let {
                        val data = result as Map<String, Any>
                        listeners.invoke {
                            val sensors = data["data"] as Map<String, Double>?
                            if (sensors != null) it.onSensorData(sensors)
                            it.onSensorStatus(data["status"] as List<Map<String, Int?>>)
                        }
                        if (!data.containsKey("status")) {
                            idleCount++
                            if (idleCount >= IDLE_AUTO_OFF) {
                                deactivate()
                            }
                        } else idleCount = 0
                    }
                }

            }
            mainHandler.post {
                backgroundChannel?.invokeMethod("sensorsData", it, handler)
            }
        }
    }

    fun deactivate() {
        stopForeground(true)
        synchronized(BACKGROUND_CHANNEL) {
            sensors?.let {
                it.destroy(this)
                sensors = null
            }
            wl?.release()
            sensorTimer?.let {
                it.cancel()
                sensorTimer = null
            }
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
        backgroundChannel?.invokeMethod("start", mapOf("profile_id" to selectedProfile), object : Result {
            override fun notImplemented() {
            }

            override fun error(errorCode: String?, errorMessage: String?, errorDetails: Any?) {
                Log.e("Recording", "Not started: $errorCode, $errorMessage")
            }

            override fun success(result: Any?) {
                listeners.invoke { it.onStatusChanged() }
            }

        })
    }

    fun pause() {
        backgroundChannel?.invokeMethod("pause", null, object : Result {
            override fun notImplemented() {
            }

            override fun error(errorCode: String?, errorMessage: String?, errorDetails: Any?) {
                Log.e("Recording", "Not paused: $errorCode, $errorMessage")
            }

            override fun success(result: Any?) {
                listeners.invoke { it.onStatusChanged() }
            }

        })
    }

    fun lap() {
        backgroundChannel?.invokeMethod("lap", null, object : Result {
            override fun notImplemented() {
            }

            override fun error(errorCode: String?, errorMessage: String?, errorDetails: Any?) {
                Log.e("Recording", "Lap error: $errorCode, $errorMessage")
            }

            override fun success(result: Any?) {
                listeners.invoke { it.onStatusChanged() }
            }

        })
    }

    fun finish(save: Boolean, callback: (Int?) -> Unit) {
        backgroundChannel?.invokeMethod("finish", mapOf("save" to save), object : Result {
            override fun notImplemented() {
            }

            override fun error(errorCode: String?, errorMessage: String?, errorDetails: Any?) {
                Log.e("Recording", "Not finished: $errorCode, $errorMessage")
            }

            override fun success(result: Any?) {
                listeners.invoke { it.onStatusChanged() }
                callback(result as Int?)
            }

        })
    }

}
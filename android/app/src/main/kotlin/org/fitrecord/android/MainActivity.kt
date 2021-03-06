package org.fitrecord.android

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothGattCharacteristic
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.fitrecord.android.service.*

class MainActivity : FlutterActivity() {
    private val IMPORT_FILE = 2
    private val REQUEST_PERMISSIONS = 1
    private val BACKGROUND_CHANNEL = "org.fitrecord/background"
    private val RECORDING_CHANNEL = "org.fitrecord/recording"
    private val SYNC_CHANNEL = "org.fitrecord/sync"
    private val PROXY_CHANNEL = "org.fitrecord/proxy"
    private lateinit var recordingChannel: MethodChannel
    private lateinit var backgroundChannel: MethodChannel
    private lateinit var syncChannel: MethodChannel
    private lateinit var profilesProxy: ChannelEngineProxy
    private lateinit var recordsProxy: ChannelEngineProxy
    private val recordingService = ConnectableServiceConnection<RecordingService>()
    private val commService = ConnectableServiceConnection<CommService>()
    private val bleService = ConnectableServiceConnection<BLEService>()

    private val listener = object : RecordingListener {
        override fun onStatusChanged() {
            runOnUiThread { recordingChannel.invokeMethod("statusChanged", null) }
        }

        override fun onSensorData(data: Map<String, Double>) {
            runOnUiThread {
                recordingChannel.invokeMethod("sensorDataUpdated", data)
            }
        }

        override fun onSensorStatus(data: List<Map<String, Int?>>) {
            runOnUiThread { recordingChannel.invokeMethod("sensorStatusUpdated", data) }
        }

        override fun onHistoryUpdated(record: Int?) {
            runOnUiThread { recordingChannel.invokeMethod("historyUpdated", mapOf("record_id" to record)) }
        }

    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        recordingService.start(this, RecordingService::class.java)
        recordingService.bind(this, RecordingService::class.java)
        bleService.bind(this, BLEService::class.java)
        commService.bind(this, CommService::class.java)
        checkPermissions()
    }

    private fun checkPermissions() {
        val permissions = arrayOf(
                Manifest.permission.ACCESS_COARSE_LOCATION,
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_BACKGROUND_LOCATION,
                Manifest.permission.BLUETOOTH,
                Manifest.permission.BLUETOOTH_ADMIN,
                Manifest.permission.READ_EXTERNAL_STORAGE,
                Manifest.permission.WRITE_EXTERNAL_STORAGE)
        val needRequest = permissions.any {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (needRequest) {
            ActivityCompat.requestPermissions(this, permissions, REQUEST_PERMISSIONS)
        }

    }

    override fun onDestroy() {
        recordingService.unbind(this)
        bleService.unbind(this)
        commService.unbind(this)
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        recordingChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RECORDING_CHANNEL)
        recordingChannel.setMethodCallHandler { call, result -> handleRecording(call, result) }
        backgroundChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKGROUND_CHANNEL)
        backgroundChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> run {
                    recordingService.async {
                        it.initFlutter(call.arguments as Long) {
                            profilesProxy = ChannelEngineProxy(flutterEngine.dartExecutor, it.dartExecutor, "$PROXY_CHANNEL/profiles")
                            recordsProxy = ChannelEngineProxy(flutterEngine.dartExecutor, it.dartExecutor, "$PROXY_CHANNEL/records")
                            runOnUiThread { result.success(null) }
                        }
                    }
                }
            }
        }
        syncChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYNC_CHANNEL)
        syncChannel.setMethodCallHandler { call, result -> handleSync(call, result) }
        recordingService.async { it.listeners.add(listener) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        recordingService.with { it.listeners.remove(listener) }
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun handleSync(call: MethodCall, result: MethodChannel.Result) {
        Log.d("Main", "Sync call: ${call.method} - ${call.arguments}")
        when (call.method) {
            "getSecrets" -> commService.with { result.success(it.getSecrets(call.arguments as String?)) }
        }

    }

    private fun handleRecording(call: MethodCall, result: MethodChannel.Result) {
        Log.d("Main", "Recording call: ${call.method} - ${call.arguments}")
        when (call.method) {
            "activate" -> recordingService.with {
                val args = call.arguments as Map<String, Object>
                it.activate(args.get("profile_id") as Int)
                result.success(0)

            }
            "deactivate" -> recordingService.with {
                it.deactivate()
                result.success(0)
            }
            "activated" -> recordingService.with { result.success(it.activated()) }
            "startSensorScan" -> bleService.with {
                Log.i("Main", "startSensorScan")
                it.startScan { id, name ->
                    it.connectDevice(id, false, GATT_SUPPORTED_SERVICES, null, object : BLEService.ConnectCallback {
                        override fun onConnect(connected: Boolean, disconnect: () -> Unit) {
                            if (connected) {
                                Log.d("Main", "Connected")
                                disconnect()
                                runOnUiThread {
                                    Log.i("Main", "sensorDiscovered $id $name")
                                    recordingChannel.invokeMethod("sensorDiscovered", mapOf("id" to id, "name" to name))
                                }
                            }
                        }

                        override fun onDisconnect(failure: Boolean) {
                            Log.w("Main", "Disconnected $failure")
                        }

                        override fun onData(chr: BluetoothGattCharacteristic) {
                        }

                    })
                }
                result.success(0)
            }
            "stopSensorScan" -> bleService.with {
                it.stopScan()
                result.success(0)
            }
            "start" -> recordingService.with {
                it.start(0)
                result.success(0)
            }
            "pause" -> recordingService.with {
                it.pause()
                result.success(0)
            }
            "lap" -> recordingService.with {
                it.lap()
                result.success(0)
            }
            "finish" -> recordingService.with {
                val args = call.arguments as Map<*, *>
                it.finish(args["save"] as Boolean) {
                    result.success(it)
                }
            }
            "export" -> commService.with { comm ->
                recordingService.with {
                    val args = call.arguments as Map<*, *>
                    comm.export(this, it.backgroundChannel, result, args["id"] as Int, args["type"] as String)
                }
            }
            "import" -> commService.with { comm ->
                comm.importStart(this, IMPORT_FILE)
                result.success(null)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (resultCode == Activity.RESULT_OK) {
            when (requestCode) {
                IMPORT_FILE -> {
                    commService.with { comm ->
                        recordingService.with { rec ->
                            comm.importComplete(data, rec.importFile())
                        }
                    }
                }
            }
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

}

package org.fitrecord.android.sensor

import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattCharacteristic.*
import android.util.Log
import org.fitrecord.android.service.*
import org.fitrecord.android.service.BLEService.ConnectCallback

class BLESensor(address: String) : Sensor() {

    private val latestData = hashMapOf<String, Double>()

    private var disconnectFn: (() -> Unit)? = null

    private val deviceCallback = object : ConnectCallback {
        
        override fun onConnect(disconnect: () -> Unit) {
            Log.d("BLESensor", "Connected $address")
            disconnectFn = disconnect
        }

        override fun onDisconnect(failure: Boolean) {
            Log.d("BLESensor", "Disconnect $address: $failure")
        }

        override fun onData(chr: BluetoothGattCharacteristic) {
            val data = hashMapOf<String, Double>()
            when (chr.uuid) {
                GATT_BATTERY_CHAR -> {
                    val battery = chr.getIntValue(FORMAT_UINT8, 0)
                    Log.d("BLESensor", "Battery: $battery")
                    data["battery"] = battery.toDouble()
                }
                GATT_HRM_CHAR -> {
                    val flags = chr.getIntValue(FORMAT_UINT8, 0)
                    val format = if ((flags and 1) != 0) FORMAT_UINT16 else FORMAT_UINT8
                    val value = chr.getIntValue(format, 1)
                    Log.d("BLESensor", "HRM: $flags $value")
                    data["hrm"] = value.toDouble()
                }
                GATT_CYCLING_POWER_CHAR -> {
                    val flags = chr.getIntValue(FORMAT_UINT16, 0)
                    val power = chr.getIntValue(FORMAT_SINT16, 2)
                    Log.d("BLESensor", "Power: $flags - $power - ${chr.value.size}")
                    data["power"] = power.toDouble()
                    val rev_count = chr.getIntValue(FORMAT_UINT16, 4)
                    val event_time = chr.getIntValue(FORMAT_UINT16, 6)
                    Log.d("BLESensor", "Crank Revolution: $rev_count, $event_time")
                }
                GATT_RUNNING_CADENCE_CHAR -> {
                    val flags = chr.getIntValue(FORMAT_UINT8, 0)
                    val speed = chr.getIntValue(FORMAT_UINT16, 1)
                    val cadence = chr.getIntValue(FORMAT_UINT8, 3)
                    cadence?.let { data["cadence"] = it * 2.0 }
                    speed?.let { data["speed_ms"] = it / 256.0 }
                    Log.d("BLESensor", "Cadence: $flags - $speed - $cadence ${chr.value.size}")
                    if (flags and 1 != 0) {
                        val stride_length = chr.getIntValue(FORMAT_UINT16, 4)
                        stride_length?.let { data["stride_len_m"] = it / 100.0 }
                        Log.d("BLESensor", "Cadence: stride $stride_length")
                    }
                    if (flags and 2 != 0) {
                        val total_distance = chr.getIntValue(FORMAT_UINT16, 6)
                        total_distance?.let { data["distance_m"] = it / 10.0 }
                        Log.d("BLESensor", "Cadence: total $total_distance")
                    }
                }
                else -> {
                    Log.d("BLESensor", "onData unexpected: $address ${chr.uuid}")
                }
            }
            synchronized(latestData) {
                if (data.isNotEmpty()) latestData.putAll(data)
            }
        }

    }

    private val bleService = object: ConnectableServiceConnection<BLEService>() {
        override fun onConnected(service: BLEService) {
            service.connectDevice(address, GATT_READ_SERVICES, GATT_READ_CHARS, deviceCallback)
        }

    }

    override fun latestData(): Map<String, Double>? {
        synchronized(latestData) {
            return latestData
        }
    }

    override fun onCreate(ctx: RecordingService) {
        bleService.bind(ctx, BLEService::class.java)
    }

    override fun onDestroy(ctx: RecordingService) {
        disconnectFn?.let { it() }
        bleService.unbind(ctx)
    }
}
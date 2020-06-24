package org.fitrecord.android.service

import android.bluetooth.*
import android.bluetooth.BluetoothGatt.GATT_SUCCESS
import android.bluetooth.BluetoothGattCharacteristic.FORMAT_UINT16
import android.bluetooth.BluetoothProfile.STATE_CONNECTED
import android.bluetooth.BluetoothProfile.STATE_DISCONNECTED
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.util.Log
import java.util.*

class BLEService: ConnectableService() {

    private var scanner: ScanCallback? = null

    private fun getAdapter(): BluetoothAdapter? {
        val bm = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        return bm.adapter
    }

    fun startScan(callback: (id: String, name: String?) -> Unit) {
//        Thread{->
//            Thread.sleep(1000)
//            callback("11:22:33:44", "Device1")
//            Thread.sleep(1000)
//            callback("12:23:34:45", "Device2")
//            Thread.sleep(1000)
//            callback("21:32:43:54", null)
//        }.start()
//        return
        val cache = hashMapOf<String, Unit>()
        val started = getAdapter()?.bluetoothLeScanner?.let {
            scanner = object: ScanCallback() {
                override fun onScanResult(callbackType: Int, result: ScanResult?) {
                    when (callbackType) {
                        ScanSettings.CALLBACK_TYPE_ALL_MATCHES -> result?.let {
                            synchronized(cache) {
                                if (!cache.containsKey(it.device.address)) {
                                    cache[it.device.address] = Unit
                                    callback(it.device.address, it.device.name)
                                }
                            }
                        }
                    }
                }
            }
            it.startScan(scanner)
            true
        }
        Log.i("BLE", "Scan started $started")
        if (started != true) throw IllegalStateException("Failed to start")
    }

    fun stopScan() {
        scanner?.let {
            getAdapter()?.bluetoothLeScanner?.stopScan(scanner)
            scanner = null
        }
    }

    interface ConnectCallback {
        fun onConnect(disconnect: () -> Unit)
        fun onDisconnect(failure: Boolean)
        fun onData(chr: BluetoothGattCharacteristic)
    }

    fun connectDevice(address: String, services: Array<UUID>, chars: Array<UUID>?, callback: ConnectCallback) {
        val opQueue = LinkedList<() -> Unit>()
        val queueOp = fun(r: (() -> Unit)?) {
            if (r != null) {
                opQueue.push(r)
            } else {
                val op = opQueue.poll()
                op?.let { it() }
            }
        }
        val cb = object: BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
                Log.d("BLE", "onConnectionStateChange $status $newState")
                when (newState) {
                    STATE_CONNECTED -> {
                        Log.d("BLE", "Connected")
                        try {
                            gatt?.discoverServices()
                        } catch (t: Throwable) {
                            Log.e("BLE", "Failed to discover", t)
                            callback.onDisconnect(true)
                        }
                    }
                    STATE_DISCONNECTED -> {
                        Log.d("BLE", "Disconnected")
                        callback.onDisconnect(false)
                    }
                }
            }

            override fun onCharacteristicRead(gatt: BluetoothGatt?, ch: BluetoothGattCharacteristic?, status: Int) {
                Log.d("BLE", "$address: onCharacteristicRead ${ch?.uuid} $status")
                if (status == GATT_SUCCESS) {
                    callback.onData(ch!!)
                }
                queueOp(null)
            }

            override fun onDescriptorWrite(gatt: BluetoothGatt?, descriptor: BluetoothGattDescriptor?, status: Int) {
                queueOp(null)
            }

            override fun onCharacteristicChanged(gatt: BluetoothGatt?, ch: BluetoothGattCharacteristic?) {
                Log.d("BLE", "$address: onCharacteristicChanged ${ch?.uuid}")
                callback.onData(ch!!)
            }
            
            override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
                Log.d("BLE", "onServicesDiscovered $status")
                val disconnect: () -> Unit = {
                    try {
                        gatt?.disconnect()
                        gatt?.close()
                    } catch (t: Throwable) {}
                }
                when (status) {
                    GATT_SUCCESS -> {
                        Log.d("BLE", "Discovered")
                        val hasService = gatt?.services?.filter {
                            val uuid = it.uuid
                            it.characteristics.forEach {
                                val canRead = (it.properties and BluetoothGattCharacteristic.PROPERTY_READ) != 0
                                val canNotify = (it.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY) != 0
                                val canIndicate = (it.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0
                                Log.d("BLE", "$address: char: ${it.uuid} - $uuid $canRead, $canNotify, $canIndicate")
                                it.descriptors.forEach {
                                    Log.d("BLE", "$address Descriptor: ${it.uuid}")
                                }
                            }
                            services.contains(uuid)
                        }?.size ?: 0 > 0
                        if (!hasService) {
                            Log.d("BLE", "Ignore device $address")
                            disconnect()
                            return
                        }
                        if (chars != null) {
                            gatt?.services?.forEach {
                                val svc = it
                                svc.characteristics.forEach {
                                    if (chars.contains(it.uuid)) {
                                        val canNotify = (it.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY) != 0
                                        val canRead = (it.properties and BluetoothGattCharacteristic.PROPERTY_READ) != 0
                                        Log.d("BLE", "$address: char2: ${it.uuid} - ${svc.uuid} $canNotify + $canRead")
                                        if (canNotify) {
                                            queueOp {
                                                val result = gatt.setCharacteristicNotification(it, true)
                                                Log.d("BLE", "$address Will be notified about: ${it.uuid} - $result")
                                                val desc = it.getDescriptor(GATT_CLIENT_DESCRIPTOR)
                                                desc.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                                                gatt.writeDescriptor(desc)
                                            }
                                        }
                                        if (canRead) {
                                            queueOp {
                                                val result = gatt.readCharacteristic(it)
                                                Log.d("BLE", "$address Will read from: ${it.uuid} - $result")
                                            }
                                        }
                                    }
                                }
                            }
                            queueOp(null)
                        }
                        callback.onConnect(disconnect)

                    }
                    else -> {
                        Log.d("BLE", "Discovery failed")
                        disconnect()
                    }
                }
            }
        }
        try {
            getAdapter()?.getRemoteDevice(address)?.connectGatt(this, true, cb)
        } catch (t: Throwable) {
            Log.e("BLE", "Failed to connect (start)", t)
            callback.onDisconnect(true)
        }
    }

    override fun onDestroy() {
        stopScan()
        super.onDestroy()
    }
}

val GATT_BATTERY_SERVICE = UUID.fromString("0000180f-0000-1000-8000-00805f9b34fb")
val GATT_BATTERY_CHAR: UUID = UUID.fromString("00002a19-0000-1000-8000-00805f9b34fb")
val GATT_HRM_SERVICE = UUID.fromString("0000180d-0000-1000-8000-00805f9b34fb")
val GATT_HRM_CHAR = UUID.fromString("00002a37-0000-1000-8000-00805f9b34fb")
val GATT_CYCLING_POWER_SERVICE = UUID.fromString("00001818-0000-1000-8000-00805f9b34fb")
val GATT_CYCLING_POWER_CHAR = UUID.fromString("00002a63-0000-1000-8000-00805f9b34fb")
val GATT_CYCLING_CADENCE_SERVICE = UUID.fromString("00001816-0000-1000-8000-00805f9b34fb")
val GATT_RUNNING_CADENCE_SERVICE = UUID.fromString("00001814-0000-1000-8000-00805f9b34fb")
val GATT_RUNNING_CADENCE_CHAR = UUID.fromString("00002a53-0000-1000-8000-00805f9b34fb")

val GATT_SUPPORTED_SERVICES = arrayOf(GATT_HRM_SERVICE, GATT_CYCLING_CADENCE_SERVICE, GATT_CYCLING_POWER_SERVICE, GATT_RUNNING_CADENCE_SERVICE)
val GATT_READ_SERVICES = arrayOf(GATT_BATTERY_SERVICE, GATT_HRM_SERVICE, GATT_CYCLING_CADENCE_SERVICE, GATT_CYCLING_POWER_SERVICE, GATT_RUNNING_CADENCE_SERVICE)
val GATT_READ_CHARS = arrayOf(GATT_BATTERY_CHAR, GATT_HRM_CHAR, GATT_CYCLING_POWER_CHAR, GATT_RUNNING_CADENCE_CHAR)
val GATT_CLIENT_DESCRIPTOR = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
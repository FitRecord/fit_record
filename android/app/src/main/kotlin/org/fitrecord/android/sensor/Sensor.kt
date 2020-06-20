package org.fitrecord.android.sensor

import android.util.Log
import org.fitrecord.android.service.RecordingService

abstract class Sensor {
    open fun onCreate(ctx: RecordingService) {}

    open fun onDestroy(ctx: RecordingService) {}

    open fun latestData(): Map<String, Double>? {
        return null
    }
}

class SensorRegistry {

    private val registry = linkedMapOf<String, Sensor>()//mapOf("time" to TimeSensor(), "location" to LocationSensor(), "sensor" to BLESensor())

    fun init(ctx: RecordingService, config: List<Map<String, Any>>) {
        synchronized(registry) {
            config.forEach {
                val id = it["id"] as String
                when (id) {
                    "time" -> registry["time"] = TimeSensor()
                    "location" -> registry["location"] = LocationSensor()
                    else -> registry[id] = BLESensor(id)
                }
            }
            Log.d("Sensors", "Init: $registry, $config")
            registry.values.forEach { sensor -> sensor.onCreate(ctx) }
        }
    }

    fun destroy(ctx: RecordingService) {
        synchronized(registry) {
            registry.values.forEach { sensor -> sensor.onDestroy(ctx) }
        }
    }

    fun collectData(): HashMap<String, Map<String, Double>> {
        val result = hashMapOf<String, Map<String, Double>>()
        synchronized(registry) {
            registry.keys.forEach {
                registry[it]?.latestData()?.apply {
                    result[it] = this
                }
            }
        }
        return result
    }

}
package org.fitrecord.android.sensor

class TimeSensor : Sensor() {

    override fun latestData(): Map<String, Double>? {
        return mapOf("now" to System.currentTimeMillis().toDouble())
    }

}
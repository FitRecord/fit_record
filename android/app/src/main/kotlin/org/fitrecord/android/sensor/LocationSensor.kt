package org.fitrecord.android.sensor

import android.content.Context
import android.location.Criteria
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.util.Log
import org.fitrecord.android.service.RecordingService

class LocationSensor : Sensor() {

    private var lastLocation: Location? = null
    private var connected = false

    private val locationListener = object : LocationListener {
        override fun onLocationChanged(location: Location?) {
            lastLocation = location
            location?.let {
                Log.d("Location", "New location: $location, ${it.provider}")
            }
        }

        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {
        }

        override fun onProviderEnabled(provider: String?) {
            Log.d("Location", "Provider enabled: $provider")
            connected = true
        }

        override fun onProviderDisabled(provider: String?) {
            Log.d("Location", "Provider disabled: $provider")
            connected = false
        }

    }

    override fun latestData(): Map<String, Double>? {
        val result = hashMapOf("connected" to if (connected) 1.0 else 0.0, "type" to 1.0)
        return lastLocation?.let {
            result["ts"] = it.time.toDouble()
            result["latitude"] = it.latitude
            result["longitude"] = it.longitude
            if (it.hasAltitude()) {
                result["altitude"] = it.altitude
            }
            if (it.hasAccuracy()) {
                result["accuracy"] = it.accuracy.toDouble()
            }
            if (it.hasSpeed()) {
                result["speed"] = it.speed.toDouble()
            }
            if (it.hasBearing()) {
                result["bearing"] = it.bearing.toDouble()
            }
            result["subtype"] = when (it.provider) {
                LocationManager.GPS_PROVIDER -> 1
                LocationManager.NETWORK_PROVIDER -> 2
                LocationManager.PASSIVE_PROVIDER -> 3
                else -> 0
            }.toDouble()
            return result
        }
    }

    override fun onCreate(ctx: RecordingService) {
        val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val criteria = Criteria()
        criteria.accuracy = Criteria.ACCURACY_FINE
        connected = false
        try {
            ctx.mainHandler.postDelayed(fun () {
//                lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 0.toFloat(), locationListener, ctx.mainLooper)
                connected = true
                lm.requestLocationUpdates(900L, 0.toFloat(), criteria, locationListener, ctx.mainLooper)
            }, 500L);
        } catch (e: SecurityException) {
            Log.e("Location", "Failed to start location", e)
        }
    }

    override fun onDestroy(ctx: RecordingService) {
        val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        lm.removeUpdates(locationListener)
        lastLocation = null
    }
}
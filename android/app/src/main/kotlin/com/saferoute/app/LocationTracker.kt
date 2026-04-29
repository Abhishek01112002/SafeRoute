package com.saferoute.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Looper
import androidx.core.app.ActivityCompat
import com.google.android.gms.location.*

data class LatLongPoint(val lat: Double, val lng: Double, val timestamp: Long)

class LocationTracker(private val context: Context, private val callback: (LatLongPoint) -> Unit) {
    
    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private var currentInterval: Long = 10000
    private var currentMinInterval: Long = 5000

    private val locationCallback = object : LocationCallback() {
        override fun onLocationResult(locationResult: LocationResult) {
            locationResult.locations.forEach { location ->
                val point = LatLongPoint(location.latitude, location.longitude, System.currentTimeMillis())
                callback(point)
            }
        }
    }

    fun startTracking() {
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(context)
        requestUpdates()
    }

    fun setTrackingRate(intervalMs: Long) {
        if (currentInterval == intervalMs) return
        currentInterval = intervalMs
        currentMinInterval = intervalMs / 2
        
        if (::fusedLocationClient.isInitialized) {
            fusedLocationClient.removeLocationUpdates(locationCallback)
            requestUpdates()
        }
    }

    private fun requestUpdates() {
        val locationRequest = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, currentInterval)
            .setMinUpdateIntervalMillis(currentMinInterval)
            .build()

        if (ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            return
        }

        fusedLocationClient.requestLocationUpdates(locationRequest, locationCallback, Looper.getMainLooper())
    }
    
    fun stopTracking() {
        if (::fusedLocationClient.isInitialized) {
            fusedLocationClient.removeLocationUpdates(locationCallback)
        }
    }
}

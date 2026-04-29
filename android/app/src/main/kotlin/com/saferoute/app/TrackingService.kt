package com.saferoute.app

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.telephony.SmsManager
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*

class TrackingService : Service() {

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private lateinit var locationTracker: LocationTracker
    private lateinit var apiManager: APIManager
    private lateinit var localDatabase: LocalDatabase
    
    private var isEmergencyModeActive: Boolean = false
    private var lastLocation: LatLongPoint? = null
    
    private val EMERGENCY_CONTACTS = listOf("+1234567890") 

    override fun onCreate() {
        super.onCreate()
        localDatabase = LocalDatabase.getDatabase(this)
        apiManager = APIManager.create(localDatabase)
        
        locationTracker = LocationTracker(this) { point ->
            lastLocation = point
            handleLocationUpdate(point)
        }
        
        createNotificationChannel()
    }

    private fun handleLocationUpdate(point: LatLongPoint) {
        serviceScope.launch {
            if (isEmergencyModeActive) {
                val success = apiManager.syncSinglePoint(point)
                if (!success) {
                    saveToDb(point)
                }
            } else {
                saveToDb(point)
                apiManager.syncAllCachedPoints()
            }
        }
    }

    private suspend fun saveToDb(point: LatLongPoint) {
        localDatabase.locationDao().insert(
            LocationPointEntity(
                latitude = point.lat,
                longitude = point.lng,
                timestamp = point.timestamp
            )
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        
        if (action == ACTION_START_SOS) {
            activateSOS()
        } else if (action == ACTION_STOP_SOS) {
            deactivateSOS()
        } else {
            // Normal start
            startForeground(NOTIFICATION_ID, createNotification("Tracking Active", false))
            locationTracker.startTracking()
        }
        
        return START_STICKY
    }

    private fun activateSOS() {
        isEmergencyModeActive = true
        Log.d("EMERGENCY", "!!! SOS ACTIVATED !!!")
        
        // CRITICAL: Must call startForeground to show the notification and promote service
        startForeground(NOTIFICATION_ID, createNotification("🚨 EMERGENCY MODE ACTIVE - HELP IS EN ROUTE", true))
        
        locationTracker.setTrackingRate(5000)
        locationTracker.startTracking() // Ensure tracking is running
        
        sendImmediateRedundantAlert()
    }

    private fun deactivateSOS() {
        isEmergencyModeActive = false
        Log.d("EMERGENCY", "SOS DEACTIVATED.")
        
        // Revert notification but stay in foreground
        startForeground(NOTIFICATION_ID, createNotification("Tracking Active", false))
        locationTracker.setTrackingRate(10000)
    }

    private fun sendImmediateRedundantAlert() {
        val lat = lastLocation?.lat ?: 0.0
        val lng = lastLocation?.lng ?: 0.0
        val message = "EMERGENCY: I need help! My last location: https://www.google.com/maps/search/?api=1&query=$lat,$lng"

        try {
            val smsManager: SmsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                this.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
            
            for (contact in EMERGENCY_CONTACTS) {
                val parts = smsManager.divideMessage(message)
                smsManager.sendMultipartTextMessage(contact, null, parts, null, null)
            }
        } catch (e: Exception) {
            Log.e("SMS", "SMS Failed: ${e.message}")
        }

        serviceScope.launch {
            apiManager.syncSinglePoint(LatLongPoint(lat, lng, System.currentTimeMillis()))
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        locationTracker.stopTracking()
        serviceScope.cancel()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotification(content: String, isEmergency: Boolean): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SafeRoute")
            .setContentText(content)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(if (isEmergency) NotificationCompat.PRIORITY_MAX else NotificationCompat.PRIORITY_LOW)
            .apply {
                if (isEmergency) {
                    setColor(0xFFFF0000.toInt())
                    setCategory(Notification.CATEGORY_ALARM)
                }
            }
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Tracking Service Channel",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Used for background location tracking and SOS alerts"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }

    companion object {
        private const val CHANNEL_ID = "TrackingServiceChannel"
        private const val NOTIFICATION_ID = 1
        const val ACTION_START_SOS = "com.saferoute.app.ACTION_START_SOS"
        const val ACTION_STOP_SOS = "com.saferoute.app.ACTION_STOP_SOS"
    }
}

package com.saferoute.app

import android.util.Log
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.Body
import retrofit2.http.POST

data class LocationBody(val latitude: Double, val longitude: Double, val timestamp: Long)
data class AlertBody(val latitude: Double, val longitude: Double, val type: String)

interface ApiService {
    @POST("location/ping")
    suspend fun sendLocationPing(@Body point: LocationBody): Response<Unit>
    
    @POST("emergency/alert")
    suspend fun triggerEmergencyAlert(@Body alertData: AlertBody): Response<String>
}

class APIManager(private val apiService: ApiService, private val localDb: LocalDatabase) {
    
    private val dao = localDb.locationDao()

    suspend fun syncSinglePoint(point: LatLongPoint): Boolean {
        return try {
            val response = apiService.sendLocationPing(LocationBody(point.lat, point.lng, point.timestamp))
            response.isSuccessful
        } catch (e: Exception) {
            Log.e("APIManager", "Network error: ${e.message}")
            false
        }
    }

    suspend fun syncAllCachedPoints() {
        val cachedPoints = dao.getUnsyncedPoints()
        if (cachedPoints.isEmpty()) return

        for (entity in cachedPoints) {
            val point = LatLongPoint(entity.latitude, entity.longitude, entity.timestamp)
            if (syncSinglePoint(point)) {
                dao.markAsSynced(entity.id)
            } else {
                // Stop syncing if network is still down
                break
            }
        }
        dao.deleteSyncedPoints()
    }

    companion object {
        private const val BASE_URL = "http://10.0.2.2:8000/" // Special Android IP for computer localhost

        fun create(localDb: LocalDatabase): APIManager {
            val retrofit = Retrofit.Builder()
                .baseUrl(BASE_URL)
                .addConverterFactory(GsonConverterFactory.create())
                .build()
            return APIManager(retrofit.create(ApiService::class.java), localDb)
        }
    }
}

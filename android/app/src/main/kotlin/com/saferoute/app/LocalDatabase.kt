package com.saferoute.app

import android.content.Context
import androidx.room.*

@Entity(tableName = "location_points")
data class LocationPointEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val latitude: Double,
    val longitude: Double,
    val timestamp: Long,
    val isSynced: Boolean = false
)

@Dao
interface LocationDao {
    @Insert
    suspend fun insert(point: LocationPointEntity)

    @Query("SELECT * FROM location_points WHERE isSynced = 0 ORDER BY timestamp ASC")
    suspend fun getUnsyncedPoints(): List<LocationPointEntity>

    @Query("UPDATE location_points SET isSynced = 1 WHERE id = :id")
    suspend fun markAsSynced(id: Long)

    @Query("DELETE FROM location_points WHERE isSynced = 1")
    suspend fun deleteSyncedPoints()
}

@Database(entities = [LocationPointEntity::class], version = 1)
abstract class LocalDatabase : RoomDatabase() {
    abstract fun locationDao(): LocationDao

    companion object {
        @Volatile
        private var INSTANCE: LocalDatabase? = null

        fun getDatabase(context: Context): LocalDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    LocalDatabase::class.java,
                    "saferoute_database"
                ).build()
                INSTANCE = instance
                instance
            }
        }
    }
}

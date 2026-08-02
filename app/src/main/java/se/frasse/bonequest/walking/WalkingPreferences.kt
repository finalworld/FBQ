package se.frasse.bonequest.walking

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.walkingDataStore by preferencesDataStore("walking_preferences")

class WalkingPreferences(private val context: Context) {
    val enabled: Flow<Boolean> = context.walkingDataStore.data.map { it[ENABLED] ?: false }
    val barkEnabled: Flow<Boolean> = context.walkingDataStore.data.map { it[BARK] ?: true }
    val vibrationEnabled: Flow<Boolean> = context.walkingDataStore.data.map { it[VIBRATION] ?: true }

    suspend fun setEnabled(value: Boolean) { context.walkingDataStore.edit { it[ENABLED]=value } }
    suspend fun setBarkEnabled(value: Boolean) { context.walkingDataStore.edit { it[BARK]=value } }
    suspend fun setVibrationEnabled(value: Boolean) { context.walkingDataStore.edit { it[VIBRATION]=value } }

    private companion object {
        val ENABLED=booleanPreferencesKey("walking_mode_enabled")
        val BARK=booleanPreferencesKey("bark_enabled")
        val VIBRATION=booleanPreferencesKey("vibration_enabled")
    }
}

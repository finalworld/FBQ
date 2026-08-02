package se.frasse.bonequest.walking

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.UUID

@Serializable
data class DistanceBatch(
    val id: String=UUID.randomUUID().toString(),
    val meters: Int,
    val startedAtEpochMillis: Long,
    val endedAtEpochMillis: Long
)

class DistanceQueue(context: Context) {
    private val preferences=context.getSharedPreferences("distance_queue",Context.MODE_PRIVATE)
    private val json=Json { ignoreUnknownKeys=true }

    @Synchronized fun load(): List<DistanceBatch> = runCatching {
        json.decodeFromString<List<DistanceBatch>>(preferences.getString(KEY,"[]") ?: "[]")
    }.getOrDefault(emptyList())

    @Synchronized fun enqueue(batch: DistanceBatch) {
        val cutoff=batch.endedAtEpochMillis-TWO_HOURS
        val updated=(load().filter { it.endedAtEpochMillis>=cutoff }+batch).takeLast(MAX_BATCHES)
        preferences.edit().putString(KEY,json.encodeToString(updated)).apply()
    }

    @Synchronized fun remove(id: String) {
        preferences.edit().putString(KEY,json.encodeToString(load().filterNot { it.id==id })).apply()
    }

    private companion object {
        const val KEY="batches"; const val MAX_BATCHES=240; const val TWO_HOURS=2*60*60*1000L
    }
}

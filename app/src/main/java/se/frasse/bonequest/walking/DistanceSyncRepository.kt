package se.frasse.bonequest.walking

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.Instant

class DistanceSyncRepository(private val client: SupabaseClient) {
    suspend fun sync(batch: DistanceBatch) {
        client.postgrest.rpc("add_distance_batch",buildJsonObject {
            put("client_batch_id",batch.id)
            put("meters",batch.meters)
            put("sample_started_at",Instant.ofEpochMilli(batch.startedAtEpochMillis).toString())
            put("sample_ended_at",Instant.ofEpochMilli(batch.endedAtEpochMillis).toString())
        })
    }

    suspend fun updatePresence(sample: LocationSample,heading: Float,isBackground: Boolean) {
        client.postgrest.rpc("update_presence",buildJsonObject {
            put("latitude",sample.latitude); put("longitude",sample.longitude)
            put("accuracy_m",sample.accuracyMeters); put("heading",heading)
            sample.reportedSpeedMps?.let { put("speed_mps",it) }
            put("is_background",isBackground)
        })
    }
}

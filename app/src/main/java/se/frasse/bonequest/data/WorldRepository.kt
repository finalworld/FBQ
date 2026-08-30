package se.frasse.bonequest

import android.util.Log
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.realtime.PostgresAction
import io.github.jan.supabase.realtime.channel
import io.github.jan.supabase.realtime.postgresChangeFlow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlin.math.cos

@Serializable
private data class WorldBoneRow(
    val id:String,val latitude:Double,val longitude:Double,
    @SerialName("bone_type") val boneType:Int,val active:Boolean,@SerialName("updated_at") val updatedAt:String?=null
)

@Serializable
private data class DirtPileRow(
    val id:String,val latitude:Double,val longitude:Double,
    @SerialName("pile_type") val pileType:Int,val cost:Int,val active:Boolean,@SerialName("updated_at") val updatedAt:String?=null
)

@Serializable
data class WorldPoop(
    val id:String,@SerialName("owner_player_id") val ownerPlayerId:String,
    @SerialName("dog_id") val dogId:String,val latitude:Double,val longitude:Double,
    @SerialName("created_at") val createdAt:String,@SerialName("expires_at") val expiresAt:String
)

@Serializable data class PoopCollectResult(@SerialName("poop_id") val poopId:String,val xp:Int)

private val worldRpcJson = Json { ignoreUnknownKeys = true }

private inline fun <reified T> decodeWorldRpcObject(raw:String):T {
    val element=worldRpcJson.parseToJsonElement(raw)
    val objectElement=if(element is JsonArray) element.firstOrNull()
        ?: error("Databasen returnerade ett tomt svar") else element
    return worldRpcJson.decodeFromString(objectElement.toString())
}

@Serializable
data class NearbyPlayer(
    @SerialName("player_id") val playerId:String,
    val latitude:Double,val longitude:Double,val heading:Float,
    @SerialName("marker_id") val markerId:String,
    @SerialName("shared_flock_ids") val sharedFlockIds:List<String>,
    @SerialName("position_age_seconds") val positionAgeSeconds:Int=0
)

@Serializable
data class MapPoi(
    @SerialName("poi_id") val poiId:String,
    @SerialName("poi_type") val poiType:String,
    val name:String?=null,val latitude:Double,val longitude:Double,
    val address:String?=null,
    @SerialName("opening_hours") val openingHours:String?=null,
    val phone:String?=null,val website:String?=null,
    @SerialName("has_game_shop") val hasGameShop:Boolean=false
)

@Serializable
data class CollectResult(
    @SerialName("collection_id") val collectionId:String,
    @SerialName("bone_type") val boneType:Int,
    @SerialName("bone_value") val boneValue:Int,
    @SerialName("rewarded_players") val rewardedPlayers:Int,
    @SerialName("player_reward") val playerReward:Long,
    @SerialName("player_balance") val playerBalance:Long
)

@Serializable
data class PileResult(
    @SerialName("claim_id") val claimId:String,
    @SerialName("bone_type") val boneType:Int,val quantity:Int,val cost:Int,
    @SerialName("reward_value") val rewardValue:Int,val balance:Long,
    @SerialName("is_double") val isDouble:Boolean
):java.io.Serializable

data class WorldSnapshot(val bones:List<Bone>,val piles:List<DirtPile>,val poops:List<WorldPoop>)
data class MapBounds(val minLat:Double,val minLon:Double,val maxLat:Double,val maxLon:Double)

class WorldRepository(private val client:SupabaseClient) {
    private val channel=client.channel("fbq-world-map")
    val worldChanges:Flow<Unit> = merge(
        channel.postgresChangeFlow<PostgresAction>(schema="public") { table="world_bones" },
        channel.postgresChangeFlow<PostgresAction>(schema="public") { table="dirt_piles" },
        channel.postgresChangeFlow<PostgresAction>(schema="public") { table="world_dog_poops" },
        channel.postgresChangeFlow<PostgresAction>(schema="public") { table="game_pois" }
    ).map { Unit }

    suspend fun subscribe() { channel.subscribe(blockUntilSubscribed=true) }

    suspend fun loadNearby(center:GeoPoint,radiusMeters:Double=2_000.0):WorldSnapshot {
        val latDelta=radiusMeters/111_320.0
        val lonDelta=radiusMeters/(111_320.0*cos(Math.toRadians(center.latitude)).coerceAtLeast(.05))
        val bones=client.from("world_bones").select {
            filter {
                eq("active",true); gte("latitude",center.latitude-latDelta); lte("latitude",center.latitude+latDelta)
                gte("longitude",center.longitude-lonDelta); lte("longitude",center.longitude+lonDelta)
            }
        }.decodeList<WorldBoneRow>().filter {
            it.hasValidMapData() &&
                distanceMeters(center.latitude,center.longitude,it.latitude,it.longitude)<=radiusMeters
        }.map { Bone(it.id,it.latitude,it.longitude,it.boneType,it.updatedAt) }
        val piles=client.from("dirt_piles").select {
            filter {
                eq("active",true); gte("latitude",center.latitude-latDelta); lte("latitude",center.latitude+latDelta)
                gte("longitude",center.longitude-lonDelta); lte("longitude",center.longitude+lonDelta)
            }
        }.decodeList<DirtPileRow>().filter {
            it.hasValidMapData() &&
                distanceMeters(center.latitude,center.longitude,it.latitude,it.longitude)<=radiusMeters
        }.map { DirtPile(it.id,it.latitude,it.longitude,it.cost,it.pileType,it.updatedAt) }
        // Keep the core world available while optional feature migrations are rolling out.
        // A missing poop table must never hide bones and dirt piles from older databases.
        val poops=runCatching {
            client.postgrest.rpc("list_visible_dog_poops",buildJsonObject {
                put("p_latitude",center.latitude);put("p_longitude",center.longitude);put("p_radius_m",radiusMeters)
            }).decodeList<WorldPoop>()
        }.recoverCatching { error ->
            // Keep compatibility while the server migration reaches every environment.
            if(!error.isMissingRpc()) throw error
            client.from("world_dog_poops").select {
                filter {
                    eq("active",true); gte("latitude",center.latitude-latDelta); lte("latitude",center.latitude+latDelta)
                    gte("longitude",center.longitude-lonDelta); lte("longitude",center.longitude+lonDelta)
                }
            }.decodeList<WorldPoop>().filter { distanceMeters(center.latitude,center.longitude,it.latitude,it.longitude)<=radiusMeters }
        }.onFailure { Log.w("FBQ-World","Kunde inte hämta synliga bajshögar",it) }
            .getOrDefault(emptyList())
        return WorldSnapshot(bones,piles,poops)
    }

    suspend fun updatePresence(point:GeoPoint,accuracy:Float,heading:Float=0f,speed:Float?=null) {
        client.postgrest.rpc("update_presence",buildJsonObject {
            put("latitude",point.latitude); put("longitude",point.longitude); put("accuracy_m",accuracy)
            put("heading",heading); speed?.let { put("speed_mps",it) }; put("is_background",false)
        })
    }

    suspend fun placeStartupTestBone(point:GeoPoint) {
        client.postgrest.rpc("place_startup_test_bone",buildJsonObject {
            put("latitude",point.latitude); put("longitude",point.longitude)
        })
    }

    suspend fun nearbyPlayers():List<NearbyPlayer> =
        client.postgrest.rpc("list_nearby_players").decodeList()

    suspend fun mapPois(bounds:MapBounds):List<MapPoi> {
        val latBuffer=(bounds.maxLat-bounds.minLat).coerceAtLeast(0.002)*0.25
        val lonBuffer=(bounds.maxLon-bounds.minLon).coerceAtLeast(0.002)*0.25
        return client.postgrest.rpc(
        "list_map_pois",buildJsonObject {
            put("min_lat",bounds.minLat-latBuffer); put("min_lon",bounds.minLon-lonBuffer)
            put("max_lat",bounds.maxLat+latBuffer); put("max_lon",bounds.maxLon+lonBuffer)
        }
        ).decodeList()
    }

    suspend fun collectNearbyBones(
        point:GeoPoint,accuracy:Float,heading:Float=0f,speed:Float?=null
    ):List<CollectResult> {
        // The map uses the phone's live position while collection is validated
        // against player_presence in Postgres. Persist this exact fix first so
        // tapping immediately after walking into range cannot race an older
        // asynchronous presence update.
        updatePresence(point,accuracy,heading,speed)
        return client.postgrest.rpc("collect_nearby_bones").decodeList()
    }

    suspend fun refreshWorld(point:GeoPoint) {
        client.postgrest.rpc("refresh_world_nearby",buildJsonObject {
            put("p_latitude",point.latitude); put("p_longitude",point.longitude)
        })
    }

    suspend fun openPile(id:String,point:GeoPoint,accuracy:Float):PileResult {
        val attempt=runCatching{client.postgrest.rpc("open_dirt_pile",buildJsonObject { put("p_pile_id",id);put("p_latitude",point.latitude);put("p_longitude",point.longitude);put("p_accuracy_m",accuracy) })}
        val response=attempt.getOrElse{error->if(!error.isMissingRpc())throw error;updatePresence(point,accuracy);client.postgrest.rpc("open_dirt_pile",buildJsonObject{put("p_pile_id",id)})}
        return response.decodeSingle()
    }

    suspend fun collectPoop(
        id:String,point:GeoPoint,accuracy:Float,heading:Float=0f,speed:Float?=null
    ):PoopCollectResult {
        val attempt=runCatching{client.postgrest.rpc("collect_dog_poop",buildJsonObject {
                put("p_poop_id",id);put("p_latitude",point.latitude);put("p_longitude",point.longitude);put("p_accuracy_m",accuracy)
            })}
        val response=attempt.getOrElse{error->if(!error.isMissingRpc())throw error;updatePresence(point,accuracy,heading,speed);client.postgrest.rpc("collect_dog_poop",buildJsonObject{put("p_poop_id",id)})}
        return decodeWorldRpcObject(response.data)
    }
}

private fun WorldBoneRow.hasValidMapData():Boolean =
    id.isNotBlank() && latitude.isFinite() && longitude.isFinite() &&
        latitude in -90.0..90.0 && longitude in -180.0..180.0 && boneType in 0..11

private fun DirtPileRow.hasValidMapData():Boolean =
    id.isNotBlank() && latitude.isFinite() && longitude.isFinite() &&
        latitude in -90.0..90.0 && longitude in -180.0..180.0 &&
        pileType in 0..4 && cost >= 0

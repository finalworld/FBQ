package se.frasse.bonequest

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
data class NearbyPlayer(
    @SerialName("player_id") val playerId:String,
    val latitude:Double,val longitude:Double,val heading:Float,
    @SerialName("marker_id") val markerId:String,
    @SerialName("shared_flock_ids") val sharedFlockIds:List<String>
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
)

data class WorldSnapshot(val bones:List<Bone>,val piles:List<DirtPile>)
data class MapBounds(val minLat:Double,val minLon:Double,val maxLat:Double,val maxLon:Double)

class WorldRepository(private val client:SupabaseClient) {
    private val channel=client.channel("fbq-world-map")
    val worldChanges:Flow<Unit> = merge(
        channel.postgresChangeFlow<PostgresAction>(schema="public") { table="world_bones" },
        channel.postgresChangeFlow<PostgresAction>(schema="public") { table="dirt_piles" },
        channel.postgresChangeFlow<PostgresAction>(schema="public") { table="game_pois" }
    ).map { Unit }

    suspend fun subscribe() { channel.subscribe(blockUntilSubscribed=true) }

    suspend fun loadNearby(center:GeoPoint,radiusMeters:Double=3_000.0):WorldSnapshot {
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
        return WorldSnapshot(bones,piles)
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

    suspend fun collectNearbyBones():List<CollectResult> =
        client.postgrest.rpc("collect_nearby_bones").decodeList()

    suspend fun openPile(id:String):PileResult = client.postgrest.rpc(
        "open_dirt_pile",buildJsonObject { put("p_pile_id",id) }
    ).decodeSingle()
}

private fun WorldBoneRow.hasValidMapData():Boolean =
    id.isNotBlank() && latitude.isFinite() && longitude.isFinite() &&
        latitude in -90.0..90.0 && longitude in -180.0..180.0 && boneType in 0..11

private fun DirtPileRow.hasValidMapData():Boolean =
    id.isNotBlank() && latitude.isFinite() && longitude.isFinite() &&
        latitude in -90.0..90.0 && longitude in -180.0..180.0 &&
        pileType in 0..4 && cost >= 0

package se.frasse.bonequest

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.UUID

@Serializable data class BoneCollectionRow(
    @SerialName("bone_type") val boneType:Int,
    @SerialName("lifetime_count") val lifetimeCount:Long,
    @SerialName("first_discovered_at") val firstDiscoveredAt:String?=null
)
@Serializable data class HomeResult(val latitude:Double,val longitude:Double,@SerialName("next_move_at") val nextMoveAt:String)
@Serializable data class SlotResult(
    @SerialName("spin_id") val spinId:String,val multiplier:Double,val payout:Int,val balance:Long,
    val rewards:kotlinx.serialization.json.JsonElement
)
@Serializable data class ShopItem(
    @SerialName("item_id") val itemId:String,@SerialName("name_sv") val nameSv:String,
    @SerialName("main_category") val mainCategory:String,val subcategory:String,
    val rarity:String,val price:Long,@SerialName("asset_name") val assetName:String,
    @SerialName("sort_order") val sortOrder:Int,val owned:Boolean,val equipped:Boolean
)
@Serializable data class PurchaseResult(
    @SerialName("purchase_id") val purchaseId:String,@SerialName("item_id") val itemId:String,
    val price:Long,val balance:Long,@SerialName("already_owned") val alreadyOwned:Boolean
)
@Serializable data class FlockSummary(
    @SerialName("flock_id") val flockId:String,val name:String,@SerialName("icon_id") val iconId:String,
    @SerialName("member_count") val memberCount:Long
)
@Serializable data class MyFlock(
    @SerialName("flock_id") val flockId:String,val name:String,@SerialName("icon_id") val iconId:String,
    @SerialName("my_role") val myRole:String,@SerialName("member_count") val memberCount:Long,
    @SerialName("bank_balance") val bankBalance:Double,@SerialName("renamed_at") val renamedAt:String?=null,
    @SerialName("created_at") val createdAt:String
)
@Serializable data class FlockMember(
    @SerialName("player_id") val playerId:String,@SerialName("display_name") val displayName:String,
    val role:String,@SerialName("joined_at") val joinedAt:String,@SerialName("bone_balance") val boneBalance:Long,
    @SerialName("total_meters") val totalMeters:Long,@SerialName("total_bones") val totalBones:Long,
    @SerialName("total_piles") val totalPiles:Long,val collection:kotlinx.serialization.json.JsonElement
)
@Serializable data class FlockApplication(
    @SerialName("player_id") val playerId:String,@SerialName("display_name") val displayName:String,
    @SerialName("created_at") val createdAt:String
)
@Serializable data class FlockLedgerEntry(
    @SerialName("entry_id") val entryId:Long,@SerialName("actor_name") val actorName:String,
    val amount:Double,@SerialName("balance_after") val balanceAfter:Double,val reason:String,
    @SerialName("created_at") val createdAt:String
)

class GameApiRepository(private val client:SupabaseClient) {
    suspend fun bootstrap():SessionBootstrap = client.postgrest.rpc("get_session_bootstrap").decodeSingle()
    suspend fun collection():List<BoneCollectionRow> = client.postgrest.rpc("get_bone_collection").decodeList()
    suspend fun changeName(name:String) = client.postgrest.rpc("change_display_name",buildJsonObject { put("player_name",name) })
    suspend fun updateSettings(walking:Boolean,bark:Boolean,vibration:Boolean) = client.postgrest.rpc(
        "update_game_settings",buildJsonObject {
            put("p_walking_mode_enabled",walking);put("p_bark_enabled",bark);put("p_vibration_enabled",vibration)
        }
    )
    suspend fun setHome():HomeResult = client.postgrest.rpc("set_home_here").decodeSingle()
    suspend fun spinHome(stake:Int):SlotResult = client.postgrest.rpc("spin_home_slot",buildJsonObject {
        put("p_client_request_id",UUID.randomUUID().toString());put("p_stake",stake)
    }).decodeSingle()
    suspend fun catalog():List<ShopItem> = client.postgrest.rpc("get_shop_catalog").decodeList()
    suspend fun buy(poiId:String,itemId:String):PurchaseResult = client.postgrest.rpc("buy_shop_item",buildJsonObject {
        put("p_poi_id",poiId);put("p_item_id",itemId);put("p_client_request_id",UUID.randomUUID().toString())
    }).decodeSingle()
    suspend fun equip(itemId:String):String = client.postgrest.rpc("equip_marker",buildJsonObject { put("p_item_id",itemId) }).decodeSingle()
    suspend fun listFlocks(search:String?=null):List<FlockSummary> = client.postgrest.rpc("list_flocks",buildJsonObject {
        if(search==null) put("search_text",kotlinx.serialization.json.JsonNull) else put("search_text",search)
    }).decodeList()
    suspend fun myFlocks():List<MyFlock> = client.postgrest.rpc("get_my_flocks").decodeList()
    suspend fun createFlock(name:String) = client.postgrest.rpc("create_flock",buildJsonObject { put("flock_name",name) })
    suspend fun applyToFlock(id:String) = client.postgrest.rpc("apply_to_flock",buildJsonObject { put("p_flock_id",id) })
    suspend fun members(id:String):List<FlockMember> = client.postgrest.rpc("get_flock_members",buildJsonObject { put("p_flock_id",id) }).decodeList()
    suspend fun applications(id:String):List<FlockApplication> = client.postgrest.rpc("get_flock_applications",buildJsonObject { put("p_flock_id",id) }).decodeList()
    suspend fun ledger(id:String):List<FlockLedgerEntry> = client.postgrest.rpc("get_flock_ledger",buildJsonObject { put("p_flock_id",id);put("p_limit",100) }).decodeList()
    suspend fun decideApplication(flockId:String,playerId:String,approve:Boolean) = client.postgrest.rpc("decide_flock_application",buildJsonObject {
        put("p_flock_id",flockId);put("p_applicant_id",playerId);put("p_approve",approve)
    })
    suspend fun setGuard(flockId:String,playerId:String,isGuard:Boolean) = client.postgrest.rpc("set_flock_guard",buildJsonObject {
        put("p_flock_id",flockId);put("p_member_id",playerId);put("p_is_guard",isGuard)
    })
    suspend fun kick(flockId:String,playerId:String) = client.postgrest.rpc("kick_flock_member",buildJsonObject { put("p_flock_id",flockId);put("p_member_id",playerId) })
    suspend fun transfer(flockId:String,playerId:String) = client.postgrest.rpc("transfer_flock_leadership",buildJsonObject { put("p_flock_id",flockId);put("p_new_leader_id",playerId) })
    suspend fun leave(flockId:String) = client.postgrest.rpc("leave_flock",buildJsonObject { put("p_flock_id",flockId) })
    suspend fun renameFlock(flockId:String,name:String) = client.postgrest.rpc("rename_flock",buildJsonObject { put("p_flock_id",flockId);put("p_new_name",name) })
    suspend fun signOut() = client.auth.signOut()
}

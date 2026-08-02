package se.frasse.bonequest

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.Google
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.flow.Flow
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

@Serializable
data class SessionBootstrap(
    @SerialName("player_id") val playerId: String,
    @SerialName("display_name") val displayName: String,
    @SerialName("onboarding_complete") val onboardingComplete: Boolean,
    @SerialName("bone_count") val boneCount: Long,
    @SerialName("total_meters") val totalMeters: Long = 0,
    @SerialName("total_bones") val totalBones: Long = 0,
    @SerialName("total_piles") val totalPiles: Long = 0,
    @SerialName("active_marker_id") val activeMarkerId: String = "marker_paw_standard",
    @SerialName("home_lat") val homeLat: Double? = null,
    @SerialName("home_lon") val homeLon: Double? = null,
    @SerialName("home_changed_at") val homeChangedAt: String? = null,
    @SerialName("walking_mode_enabled") val walkingModeEnabled: Boolean = false,
    @SerialName("bark_enabled") val barkEnabled: Boolean = true,
    @SerialName("vibration_enabled") val vibrationEnabled: Boolean = true,
    @SerialName("is_admin") val isAdmin: Boolean,
    @SerialName("is_suspended") val isSuspended: Boolean,
    @SerialName("requires_new_name") val requiresNewName: Boolean,
    @SerialName("created_at") val createdAt: String = ""
    ,@SerialName("level") val level: Int = 1
    ,@SerialName("xp_total") val xpTotal: Double = 0.0
    ,@SerialName("xp_current_level") val xpCurrentLevel: Double = 0.0
    ,@SerialName("xp_next_level") val xpNextLevel: Double = 0.0
    ,@SerialName("xp_from_bones") val xpFromBones: Double = 0.0
    ,@SerialName("xp_from_walking") val xpFromWalking: Double = 0.0
    ,@SerialName("xp_from_piles") val xpFromPiles: Double = 0.0
    ,@SerialName("pending_level_from") val pendingLevelFrom: Int? = null
    ,@SerialName("pending_level_to") val pendingLevelTo: Int? = null
    ,@SerialName("pending_level_bones") val pendingLevelBones: Long = 0
    ,@SerialName("pending_level_notice") val pendingLevelNotice: Boolean = false
)

class AuthRepository(private val client: SupabaseClient) {
    val sessionStatus: Flow<SessionStatus> = client.auth.sessionStatus

    suspend fun signInWithGoogle() = client.auth.signInWith(
        provider = Google,
        redirectUrl = "frassesbonequest://login-callback"
    )
    suspend fun signOut() = client.auth.signOut()

    suspend fun loadBootstrap(): SessionBootstrap =
        client.postgrest.rpc("get_session_bootstrap").decodeSingle()

    suspend fun completeProfile(name: String): SessionBootstrap {
        client.postgrest.rpc(
            function = "complete_profile",
            parameters = buildJsonObject { put("player_name", name) }
        )
        return loadBootstrap()
    }
}

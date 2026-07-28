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
    @SerialName("is_admin") val isAdmin: Boolean,
    @SerialName("is_suspended") val isSuspended: Boolean,
    @SerialName("requires_new_name") val requiresNewName: Boolean
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

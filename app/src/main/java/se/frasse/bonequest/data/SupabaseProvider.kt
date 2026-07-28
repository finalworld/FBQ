package se.frasse.bonequest

import android.content.Intent
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.FlowType
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.handleDeeplinks
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.realtime.Realtime
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

object SupabaseProvider {
    private val _authCallbackError = MutableStateFlow<String?>(null)
    val authCallbackError = _authCallbackError.asStateFlow()

    val clientOrNull: SupabaseClient? by lazy {
        if (!SupabaseBackend.configured) null else createSupabaseClient(
            supabaseUrl = BuildConfig.SUPABASE_URL,
            supabaseKey = BuildConfig.SUPABASE_ANON_KEY
        ) {
            install(Auth) {
                scheme = "frassesbonequest"
                host = "login-callback"
                flowType = FlowType.PKCE
            }
            install(Postgrest)
            install(Realtime)
        }
    }

    suspend fun handleAuthDeepLink(intent: Intent) {
        val client = clientOrNull ?: return
        _authCallbackError.value = null
        client.auth.awaitInitialization()
        client.handleDeeplinks(
            intent = intent,
            onSessionSuccess = { _authCallbackError.value = null },
            onError = { error ->
                _authCallbackError.value = error.message
                    ?.takeIf(String::isNotBlank)
                    ?: error::class.simpleName
                    ?: "Okänt fel vid Google-inloggningen"
            }
        )
    }

    fun clearAuthCallbackError() {
        _authCallbackError.value = null
    }
}

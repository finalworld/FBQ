package se.frasse.bonequest

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.FlowType
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.realtime.Realtime

object SupabaseProvider {
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
}

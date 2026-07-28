package se.frasse.bonequest

import android.content.Context
import android.content.Intent
import android.net.Uri

object SupabaseBackend {
    val configured: Boolean get() = BuildConfig.SUPABASE_URL.isNotBlank() && BuildConfig.SUPABASE_ANON_KEY.isNotBlank()
    fun startGoogleLogin(context: Context) {
        if (!configured) return
        val redirect = Uri.encode("frassesbonequest://login-callback")
        val url = "${BuildConfig.SUPABASE_URL}/auth/v1/authorize?provider=google&redirect_to=$redirect"
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    }
}

# Supabase-anslutning för Android

Hemligheter ska inte checkas in i Git. Lägg följande i användarens globala
`%USERPROFILE%/.gradle/gradle.properties`:

```properties
SUPABASE_URL=https://btlcbknnqeoodnadjifw.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

Använd projektets **publishable key**, aldrig `service_role` eller secret key.

I Supabase Dashboard:

1. Aktivera Google under Authentication > Providers.
2. Lägg till `frassesbonequest://login-callback` under tillåtna Redirect URLs.
3. Google OAuth-klientens callback till Supabase är
   `https://btlcbknnqeoodnadjifw.supabase.co/auth/v1/callback`.

Appen använder PKCE. Android tar emot callbacken via manifestets deep link och
supabase-kt återställer och uppdaterar sessionen säkert.

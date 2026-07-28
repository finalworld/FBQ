# Frasse's Bone Quest v0.300
Included: 12 named/value bone sprites, 5 dirt-pile sprites, fixed-left/stretch-center/fixed-right HUD, supplied wooden collect button, 25 m collection, multi-bone collection, loading/feedback, player profile/statistics, MapLibre path spawning, no P2P, Google OAuth entry point, Supabase schema and cloud-ready configuration.

Before cloud login works, add to `gradle.properties`:
SUPABASE_URL=https://YOUR_PROJECT.supabase.co
SUPABASE_ANON_KEY=YOUR_ANON_KEY

Then enable Google provider in Supabase and add redirect URL `frassesbonequest://login-callback`.
Run `SUPABASE_SETUP.sql` in Supabase. Server-authoritative collection/respawn RPCs still require deployment in the Supabase project; credentials cannot be embedded without the project values.

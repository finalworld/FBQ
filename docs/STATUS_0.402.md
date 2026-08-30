# Frasses Bone Quest 0.402 – lokal teststatus

Den här versionen innehåller de överenskomna rättningarna och XP-systemet. Valpsystemet och den större omritningen av kartan är medvetet sparade till senare.

## Ingår i 0.402

- XP från promenader, lösa ben och jordhögar, serverberäknad level 1–100 och level-belöningar.
- Gul XP-rad längst ned med tio delar och aktuell level.
- Level-up-ruta som väntar sist i meddelandekön, visar summering och kräver ett medvetet tryck för att stängas.
- Ljud och vibration vid level-up enligt spelarens befintliga ljud- och vibrationsinställningar.
- Kompakt åtgärdsrad: en knapp använder hela bredden, två delar 50/50 och tre delar lika.
- Stabilare promenadmätning som filtrerar orimliga GPS-hopp och inte fortsätter när appen uttryckligen stängs.
- Mer tolerant fysisk interaktion för telefoner med sämre GPS, utan att tillåta distansspel.
- Delade ben uppdateras löpande för båda spelarna och visar ett tydligt gemensamt belöningsmeddelande.
- Admin kan söka spelare, ge ben, ta ben eller sätta ett exakt bensaldo och spara ändringen.
- Flockmedlemmars level visas i medlemslistan.
- Nya tydliga 12 bentyper med logiska svenska namn.
- Fem omritade jordhögar med tydligare storleks- och värdeskillnad.
- Hundtemad enarmad bandit med nitlott och synlig vinst-/chanslista.
- Komplett pixelgrafiskt butiksark där hundraser och leksaker matchar sin text.
- Inställningsikon och röd pixelgrafisk avstängningsikon i samma visuella stil.
- Världsinfo visas längre och kan visa `Byter om 2 t 14 min` utan sekunder.
- Apptext låses till 100 % så systemets textskalning inte förstör layouten.

## Databassteg före test

Kör hela filen `supabase/migrations/20260802120000_xp_system_and_runtime_fixes.sql` i Supabase SQL Editor. Den innehåller tabeller, RPC-funktioner och rättigheter som APK:n förväntar sig. APK:n kan installeras utan detta, men de nya serverfunktionerna fungerar inte förrän migreringen är körd.

## Sparat till framtiden

- Valp- och hundsystemet, inklusive Lyckliga Svansars Hundstall.
- Den stora pixel-RPG-omritningen av kartan.
- Achievements och större långsiktiga användningsområden för stora benförmögenheter.

## Kort testordning

1. Logga in på två telefoner och kontrollera GPS-positionerna utomhus.
2. Ta samma lösa ben tillsammans och verifiera direkt saldo, meddelande och borttagning på båda telefonerna.
3. Testa ett ben med sämre GPS och bekräfta att rimlig tolerans används.
4. Öppna jordhög och hemmets bandit; kontrollera nitlott, belöning och vinstlista.
5. Handla minst en hundras och en leksak; kontrollera bild, namn, köp och utrustning.
6. Sök spelare i admin och testa ge, ta samt sätt exakt bensaldo.
7. Gå en kort provsträcka, låt telefonen ligga still och kontrollera att falsk distans inte räknas.

# Framtida funktioner

Den här listan innehåller godkända idéer som ska bevaras för senare utveckling men inte implementeras förrän Daniel uttryckligen säger till.

## HUD: saldo och promenaddistans

**Status:** Ska justeras senare. Inte påbörjat.

- Ta bort de svarta fyrkantiga bakgrunderna bakom både benikonen och distansikonen. Ikonerna ska ligga direkt mot HUD-panelens ljusa bakgrund och behålla god kontrast.
- Behåll benikonen bredvid spelarens bensaldo.
- Ersätt tassikonen bredvid promenaddistansen med tydliga mänskliga fotspår, eftersom värdet visar hur långt spelaren själv har gått.
- Luta fotspåren cirka 45 grader så att de ser ut som steg i rörelse.
- Anpassa storlek, kantlinje och pixelskärpa till samma RPG/pixelstil som resten av den fastslagna HUD-designen.

## Butik: felaktiga föremålsbilder

**Status:** Måste rättas. Inte påbörjat.

- Nästan alla föremålsbilder i butiken visar fel utsnitt eller fel del av ikonarket.
- Granska samtliga butikskategorier och samtliga föremål, inte bara de objekt där felet först upptäcktes.
- Koppla varje föremål till rätt ikon och säkerställ att beskärning, atlasposition och bildresurs är korrekt.
- Varje kort ska visa en komplett, centrerad och tydligt igenkännbar bild utan delar från angränsande ikoner.
- Behåll den fastslagna söta pixel/RPG-stilen och kontrollera resultatet i faktisk mobilstorlek.

## Admin: spelaradministration fungerar inte

**Status:** Blockerande bugg som ska fixas nu.

- Admin kan fortfarande inte ändra eller ge ben till en spelare.
- Kontrollera hela kedjan: spelarsökning, val av spelare, inmatning av nytt belopp eller förändring, aktiverad åtgärdsknapp, bekräftelse, server-RPC, adminbehörighet/RLS och uppdatering av gränssnittet.
- Det ska tydligt gå att lägga till och dra av ben, men saldot får aldrig bli negativt.
- En synlig och fungerande bekräftelse-/sparaknapp ska finnas när en giltig ändring har angetts.
- Lyckad ändring ska synas direkt för både admin och den berörda spelaren utan omstart av appen.
- Misslyckade ändringar ska visa ett begripligt svenskt felmeddelande i stället för att knappen bara är grå eller ingenting händer.
- Alla adminändringar ska fortsätta loggas med administratör, berörd spelare, förändring, orsak och tidpunkt.

## Admin: placerade kartobjekt kan inte tas bort

**Status:** Bugg/saknad adminfunktion som ska fixas nu.

- Admin kan placera ut kartobjekt men saknar möjlighet att ta bort dem igen.
- I adminredigering ska ett befintligt objekt kunna markeras direkt på kartan.
- Det markerade objektets typ, värde/nivå, koordinater och placeringskälla ska visas innan någon åtgärd görs.
- En separat tydlig `Ta bort`-knapp ska finnas och kräva bekräftelse. Att förhandsvisa eller testa objektet får aldrig radera det.
- Borttagningen ska fungera för bland annat lösa ben, jordhögar, butiker och andra manuellt placerade permanenta platser.
- Objektet ska försvinna direkt för alla anslutna spelare och får inte automatiskt återskapas om det är manuellt borttaget eller spärrat.
- Åtgärden ska valideras på servern, kräva adminbehörighet och loggas med administratör, objekttyp, objekt-ID, position, orsak och tidpunkt.

## Delat ben: den andra spelarens app uppdateras inte

**Status:** Blockerande synkbugg som ska fixas nu.

- När flera berättigade spelare befinner sig inom benets plockradie och en av dem tar benet får alla korrekt belöning i databasen, men spelaren som inte tryckte ser inte förändringen förrän appen startas om.
- Alla mottagares bensaldo ska uppdateras automatiskt och snabbt utan omstart eller manuell omladdning.
- Det plockade benet ska försvinna från kartan för samtliga anslutna spelare samtidigt.
- Den passiva mottagaren ska få en liten, icke-spammande svensk bekräftelse på benets typ och värde.
- Lösningen ska hantera både Supabase Realtime-händelser och en säker periodisk reservuppdatering om en realtidshändelse missas.
- Prenumerationer ska återanslutas efter nätverksbyte, bakgrundsläge och återgång till appen utan dubbla händelser eller dubbla belöningar.

## Enarmade banditer: ny hundtematisk pixelgrafik

**Status:** Godkänd visuell riktning för senare implementation.

- Både jordhögarnas belöningssnurra och hemmaautomaten ska utformas som en charmig hundtematisk pixelautomat i samma RPG-stil som referensbilden.
- Automaten ska ha ett stort tydligt rullfönster, fysisk spak, trä/metallram, guldaccenter, tassdetaljer och Frasse-färgskalan.
- I rullfönstret ska spelets riktiga ben rulla förbi i stället för hundkroppar, kronor eller generiska symboler.
- Benens riktiga grafik och kvalitetsnivåer ska vara lätta att känna igen även medan rullen är i rörelse.
- Pris-/vinstpanelen ska använda korrekta benvärden och sannolikheter för den aktuella jordhögen eller den valda insatsen. Referensbildens värden ska inte kopieras.
- Jordhögens resultat bestäms säkert av servern innan animationen visas. Rullen är en cirka tre sekunder lång presentation av det redan fastställda resultatet och får inte påverka utfallet.
- Hemmaautomaten använder samma visuella grunddesign men cirka fem sekunders animation och visar vald insats på 1, 2, 5 eller 10 ben samt en korrekt vinsttabell.
- Om två spelare försöker öppna samma jordhög visar förloraren ingen falsk vinst: animationen avbryts, insatsen återbetalas och ett tydligt meddelande visas.
- Animationerna ska kunna hoppas över utan att belöning, återbetalning eller serverstatus påverkas.

## Flockbank: summerad bidragstopplista

**Status:** Ska ändras.

- Flockbanken ska inte visa varje enskilt benbidrag eller varje transaktion som en separat rad.
- Visa i stället exakt en rad per medlem med personens sammanlagda bidrag till den aktuella flocken.
- Exempel: `Danne – 428 ben`.
- Sortera listan som en topplista med störst totalt bidrag överst.
- Visa spelarens placering, namn och totalt bidrag i hela ben. Vid samma totalsumma får spelarna samma placering eller sorteras stabilt efter namn.
- Spelarens egen rad ska vara lätt att hitta och markeras diskret utan att bryta sorteringen.
- Summan gäller endast bidrag till den flock vars bank visas. Bidrag till spelarens andra flockar räknas separat.
- Topplistan ska uppdateras automatiskt när flocken får nya bidrag, utan att varje bakomliggande transaktion behöver visas i gränssnittet.

## Huvudmeny: öppning, stängning och appavslut

**Status:** Ska ändras.

- När huvudmenyn öppnas ska meny-/navigationspanelen ligga kvar synlig samtidigt som spelarens profilsida visas direkt i innehållsytan bredvid den. Profilen är standardvalet men ersätter eller döljer inte själva menyn.
- När ett annat menyval trycks byts endast innehållsytan; meny-/navigationspanelen ska fortsätta vara synlig tills spelaren uttryckligen stänger den med hamburgarknappen, `Stäng` eller telefonens tillbaka-knapp.
- Menyknappen ska vara en tydlig klassisk hamburgarikon med tre horisontella streck.
- Samma hamburgarknapp ska fungera som växel: ett tryck öppnar menyn och nästa tryck stänger den.
- När menyn är öppen kan texten `Stäng` visas direkt till höger om hamburgarikonen för att göra funktionen tydlig.
- Den nuvarande separata `Stäng`-kontrollen längst till höger på skärmen ska tas bort.
- Telefonens systemknapp/gest för tillbaka ska först navigera tillbaka inom menyn och därefter stänga menyn på samma sätt som hamburgarknappen.
- `Stäng appen` ska flyttas till en fast plats längst ner i menyn och alltid ligga kvar vid botten även när menyinnehållet scrollas.
- Appavslut ska visas som en klassisk strömknapp: en cirkel med ett kort lodrätt streck upptill, tillsammans med en tydlig svensk etikett.
- Strömknappen ska stänga appen och avsluta promenadläget enligt den redan fastslagna regeln; den får inte misstas för vanlig menystängning eller utloggning.

## Jordhögar: större och tydligare nivåikoner

**Status:** Ska ändras.

- Alla jordhögsikoner på kartan ska göras lite större, men inte så stora att de täcker vägar, ben eller andra viktiga kartobjekt.
- Högnivåerna ska kunna skiljas åt direkt utan att spelaren behöver trycka på dem.
- Ge varje nivå en tydligt egen silhuett samt märkbara skillnader i högens storlek, jordfärg, benfragment, stenar, växtlighet och eventuella glimteffekter.
- Skillnaderna får inte bygga enbart på små färgskiftningar; de ska även fungera för färgsvaga spelare och på små mobilskärmar.
- Behåll samma söta hundtematiska pixel/RPG-stil som HUD, ben och den planerade jordhögsautomaten.
- En tryckning ska fortfarande visa kostnad och detaljer, men spelaren ska redan före tryck kunna uppskatta vilken typ av hög det är.
- Kontrollera alla nivåer sida vid sida och på faktisk karta vid flera zoomnivåer innan grafiken godkänns.

## Profil: markörer visar interna ID:n

**Status:** Visnings-/lokaliseringsbugg som ska fixas nu.

- Profilsidan visar interna tekniska markör-ID:n, exempelvis `marker_frasse_mythic`, i stället för korrekta användarnamn.
- Samtliga markörer ska visa sitt svenska visningsnamn, exempelvis `Frasse`, på profilsidan och överallt annars där markören omnämns.
- Interna databasnycklar och resursnamn får aldrig visas för spelaren.
- Visningsnamnen ska hämtas genom spelets översättningssystem så att framtida språk kan läggas till utan att databas-ID:n ändras.
- Om en översättning saknas ska gränssnittet visa ett begripligt reservnamn och logga felet, inte skriva ut rånyckeln.
- Kontrollera profil, utrustning, butik, köphistorik, adminvyer och eventuella felmeddelanden för alla markörkategorier.

## Promenadläge: GPS-drift ger falsk gångdistans

**Status:** Viktig distans-/belöningsbugg som ska fixas nu.

- En stillaliggande telefon kan förflyttas små eller stora sträckor av GPS-drift och registrerar ibland kilometer medan spelaren sover.
- Punkter med dålig noggrannhet ska inte räknas. Noggrannhetsgränsen ska vara adaptiv och en ny GPS-punkt ska inte godkännas bara för att den ligger långt från den förra.
- Små rörelser inom GPS-signalens felcirkel ska räknas som stillastående och ge 0 meter.
- Orimliga hopp, omöjlig gånghastighet och punkter med för lång eller för kort tidslucka ska avvisas eller bryta sträckan i stället för att kopplas ihop.
- Distans ska kräva flera sammanhängande trovärdiga gångpunkter innan den bokförs. En ensam avvikande punkt får aldrig skapa kilometer.
- När enheten varit stilla en längre tid ska en ny rörelseserie behöva stabiliseras innan distansräkningen återupptas.
- Om tillgängligt kan rörelsesensorer/aktivitetsigenkänning användas som extra stöd, men riktig promenad får fortfarande fungera på telefoner där detta saknas eller nekas.
- Kartmarkören ska mjukas visuellt så GPS-brus inte får spelaren att hoppa fram och tillbaka, utan att den visade positionen blir märkbart fördröjd under riktig promenad.
- Servern ska rimlighetskontrollera inskickade distanssegment och aldrig dela ut kilometerbelöning för avvisad GPS-drift.
- Testfall ska omfatta telefon stilla över natten, dålig inomhus-GPS, skärm av/på, nätverksbyte, GPS-bortfall, vanlig promenad och korta stopp.

## Hundsystem

**Status:** Planerat för framtiden. Inte påbörjat.

**Designkälla:** `Frasses_Bone_Quest_GDD_Hundsystem_v0.2_Lattlast.docx`.

- En jordhög ger alltid sin vanliga belöning och har därefter en liten chans att utlösa ett extra möte med en ensam valp i närheten.
- Spelaren kan adoptera valpen eller skicka den till hundstallet. Hundstallet är ett vänligare namn för permanent borttagning och ger ingen belöning.
- Endast en valp kan växa åt gången. Den måste vara aktiv och växer genom registrerad promenaddistans.
- Om en ny valp hittas medan en annan växer måste spelaren välja vilken som ska behållas; den andra skickas permanent till hundstallet.
- Valpar blir vuxna efter 5, 7 eller 10 km beroende på rank. Rank avgör vilka perk-pooler hunden kan få egenskaper från.
- Obegränsat antal vuxna hundar kan samlas, men endast en hund kan vara aktiv och endast dess perks gäller.
- När valpen blir vuxen avslöjas utseende och perks. En sällsynt specialvariant får finare utseende och två perks.
- Föreslagna perks: Benexperten, Samlaren, Benmagneten, Vandrarkompisen, XP-specialisten, Bensamlaren och Skattletaren.
- Exakta valpchanser, rankchanser, specialvariantchans, perk-pooler, staplingsregler och balansvärden ska spikas före implementation.

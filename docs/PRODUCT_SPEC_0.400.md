# Frasse's Bone Quest 0.400 — låst produktspecifikation

Status: godkänd för implementation 2026-07-28. Den här filen är facit för version 0.400.

## Grundidé

FBQ är ett enkelt svenskt promenadspel. Kartan och korta interaktioner ska få spelaren att fortsätta gå; spelet ska aldrig kräva långa stopp utom vid hemmet och fysiska hundrelaterade platser. All spelar- och världskritisk logik avgörs av Supabase, aldrig av klienten.

## Plattform, språk och utseende

- Android, porträttläge. Statusfält och telefonens navigationsfält ska alltid vara synliga.
- Hela gränssnittet är svenskt men alla texter ligger i Android-resurser för framtida språk.
- Pixel-RPG-karta med verkliga vägar, stigar och svenska gatunamn. Skog, vatten, parker och byggnader följer samma tema. Vanliga POI-ikoner döljs.
- Kartan är alltid norr upp, följer spelaren tills kartan flyttas manuellt och har en återcentreringsknapp.
- Färger hämtas från Frasse: aprikos/guld, kräm, kolsvart, selens turkos, sjöblått och skogsgrönt.
- HUD ligger kant i kant under statusfältet: hamburgermeny, lodrät delare, logotyp, benikon och helt benantal. Ingen ytterram; endast tunn guldunderkant. Antalet ska minst rymma `1 000 000 000` och krymper vid behov.
- Appikon: Frasses pixelhuvud med turkos detalj, mörk botten och guldkant; adaptiv och monokrom variant.
- Små statusmeddelanden ligger längst ned, döljs bakom aktionsknappar, dedupliceras och visas normalt i två sekunder.

## Konto och profil

- Google-inloggning är obligatorisk; inget gästkonto. Google ger identiteten, Supabase lagrar speldata.
- Före kartan väljs ett icke-unikt spelarnamn: 3–20 bokstäver, siffror och mellanslag. Mellanslag normaliseras. Namnet kan ändras en gång per 24 timmar, serverstyrt.
- Profilen visar namn, aktiv markör, bensaldo, total distans, totalt insamlade ben, jordhögar, medlem sedan och länk till bensamlingen.
- Kontot kan loggas ut och raderas med dubbel bekräftelse. Flockledare måste först överföra ledarskapet. Historiska flockposter anonymiseras som `Borttagen spelare`.
- Hempositionen är privat, även för flockmedlemmar.

## Position och promenadläge

- Distans räknas med kartan öppen och via Promenadläge. Punkter över cirka 12 km/h, GPS-hopp och dålig noggrannhet filtreras bort.
- Promenadläge aktiveras en gång i Inställningar. Därefter startas en foreground location service när appen öppnas; skärmen kan släckas utan extra startknapp. Permanent notis visar distans, närliggande ben och `Avsluta promenad`.
- Force-stop eller omstart kräver att appen öppnas igen.
- Skall och vibration har separata reglage, båda på från början. Inom benzon spelas ett vänligt skall och en vibration en gång per grupp tills zonen lämnats.
- Aktiv närvaro uppdateras var 5:e sekund med skärmen på och var 10:e sekund med skärmen av. Närvaro äldre än 15 sekunder får ingen gruppbelöning.
- Andra aktiva spelare visas inom 200 meter med sin markör, utan namn. Upp till tre små färgprickar visar gemensamma flockar. Markörerna är passiva.
- Offline fungerar karta och lokal distans. Ben, högar, butik och automater låses. Högst två timmar rimliga GPS-punkter köas för distanssynk.

## Lösa ben

- Världen är global. Ett ben försvinner för alla när det tas.
- En tryckning tar alla lösa ben inom 25 meter. Spelaren måste ha GPS-noggrannhet högst 30 meter.
- Alla aktiva spelare inom 25 meter med färsk närvaro och god GPS får benets fulla typ och värde.
- Varje belönad spelare ger dessutom 10 % av värdet till var och en av sina flockar. Spelaren behåller hela värdet. Bidraget gäller endast lösa världsben och får aldrig dubblas för samma spelare/flock/ben.
- Ben ligger normalt 250–350 meter från varandra på eller nära gångbara vägar. Sällsynta undantag tillåts. Aldrig i vatten, byggnader eller otillgänglig mark.
- Efter plockning skapas ett nytt ben efter cirka 5 minuter på en ny lämplig plats, normalt minst 250 meter från den gamla och andra ben, med ny slumpad typ.
- Ben och högar hämtas högst 5 km från spelarens verkliga GPS-position, oavsett kartpanorering. Borttagning synkas i realtid och animeras med en kort pixelglimt.
- Tryck på avlägset ben visar namn, värde och avstånd. `Ta benet` visas endast inom räckvidd.

| Nr | Typ | Värde | Spawnvikt |
|---:|---|---:|---:|
| 1 | Sprucket | 1 | 42 % |
| 2 | Slitet | 2 | 23 % |
| 3 | Mossigt | 3 | 14 % |
| 4 | Polerat | 5 | 8,5 % |
| 5 | Rent | 8 | 5 % |
| 6 | Kristallben | 12 | 3 % |
| 7 | Magiskt | 20 | 1,8 % |
| 8 | Gyllene | 35 | 1,1 % |
| 9 | Safir | 60 | 0,7 % |
| 10 | Diamant | 100 | 0,5 % |
| 11 | Prismaben | 175 | 0,3 % |
| 12 | Frasses kungaben | 300 | 0,1 % |

- Livstidsantal sparas per typ och minskar aldrig. Gruppbelöningar, högar och hemmaautomaten räknas.
- Bensamlingen visar alla tolv typer med bild, namn, värde och livstidsantal; oupptäckta visas som siluetter.

## Jordhögar

- Fem nivåer kostar 10, 25, 50, 100 och 250 ben.
- Först till serverbekräftad betalning vinner atomärt. Förloraren debiteras aldrig och får `En annan spelare hann före`.
- Högar ligger normalt 750–1000 meter isär; ungefär 2–4 syns lokalt. Efter 5–10 minuter återkommer högen 500–1000 meter från sin gamla plats på gångbar mark.
- Exakt ett normalt ben vinns alltid och dess värde är minst kostnaden. Exakt återbetalning ska vara relativt ovanlig och vinst vanlig; liten chans finns till stor vinst.
- Dubbelvinst per nivå: 0,1 %, 0,2 %, 0,4 %, 0,7 %, 1,0 %. Vid dubbelvinst viktas typen: 50 % två lägsta giltiga, 25 % nästa, 12 % nästa, 7 % nästa och 6 % högre, där exakt bästa möjliga typ är 1 % av dubbelvinsterna. För 250-högen blir dubbelvinst två kungaben.
- Servern bestämmer resultatet. Hundtematisk snurra pågår högst tre sekunder och kan hoppas över.
- Första knappen visar pris och är grå med `Behöver X ben` om saldot är för lågt. En separat ruta har den verkliga `Betala X ben`-knappen.

## Hemmet och hemmaautomaten

- Hemmet sätts vid aktuell GPS med `Sätt mitt hem här`, inom 50 meter och god noggrannhet. Flytt har exakt 24 timmars servercooldown.
- Ägarens husikon syns oavsett avstånd när platsen finns i vyn. Fjärrtryck visar information, avstånd och cooldown; funktionerna används endast inom 50 meter.
- Automaten är hundtematisk, serverstyrd, fem sekunder och kan hoppas över. Insatser: 1, 2, 5 eller 10 ben, en manuell omgång åt gången, ingen autoplay.
- Utfall: 55 % förlust, 25 % 1×, 15 % 2×, 4 % 5×, 0,9 % 10× och 0,1 % 50×. Inga riktiga pengar eller uttag.

## Flockar

- En spelare får vara med i högst tre flockar. Namn är unika utan hänsyn till versaler, 3–24 bokstäver/siffror/mellanslag, normaliserade.
- Det kostar spelaren 500 ben att skapa en flock. Ansökan är gratis och möjlig endast med ledig flockplats.
- Roller: exakt en `Flockledare`, samt `Flockvakt` och `Flockmedlem`. Ledaren kan befordra/sänka vakter. Vakter kan hantera ansökningar och sparka vanliga medlemmar, men inte vakter eller ledaren.
- Ledaren måste överföra ledarskap före utträde. En flock kan endast tas bort när ledaren är ensam, efter dubbel bekräftelse.
- Offentlig lista visar flockikon, unikt namn och medlemsantal. Ledare, bank och statistik visas endast för medlemmar.
- Medlemmar kan se varandras namn, total km, totalt/löpande bensaldo, typstatistik och antal högar via `Mina flockar > Medlemmar`.
- Flockbanken lagrar decimaler och visas med en decimal. Alla medlemmar ser saldo och liggare med medlem, belopp, orsak och tid. Endast ledaren spenderar i 0.400.
- Omdöpning kostar 500 flockben, har sju dagars cooldown och görs endast av ledaren.
- Gratis standardikon är en tassköld. Datamodellen förbereds för framtida ikonbutik finansierad av flockbanken.

## Butik och utrustning

- Fysiska butiker används endast inom 50 meter. De skapas automatiskt vid hundrastgårdar och djurbutiker; veterinärer och hundtrim/tvätt är informationsplatser. Admin kan korrigera allt.
- `Besök butik` visas i aktionsstacken. Butiken är helskärm med fast, nästlad kategorimeny till vänster och rutnät till höger; bensaldo och stängknapp upptill.
- Butiken köper bara. Ägda saker är grå, märkta `ÄGS` och inaktiva. För dyra saker behåller färgen men har rött pris/låst köp. Förhandsvisning och uttryckligt köp krävs.
- `Min utrustning` i huvudmenyn används för att välja markör. Alla butiker har samma sortiment i 0.400.
- 96 startmarkörer: 1 gratis standardtass; 30 vanliga á 50; 24 ovanliga á 150; 18 sällsynta á 500; 14 episka á 1 500; 8 legendariska á 5 000; Frasse som mytisk á 10 000.
- Kategorier: Hundraser 36, Hundleksaker 20, Tassar 12, Halsband/namnbrickor 10, Koppel/utrustning 8, Emblem/övrigt 10.
- Frassemarkören bygger på Frasses aprikosfärgade lockiga huvud, svarta nos, hängöron och turkosa sele med särskild guldram. Den kostar andra 10 000 ben men ges permanent gratis till ägarens uttryckligen konfigurerade konto.

## Hundrelaterade kartplatser

- OSM/Overpass: `leisure=dog_park`, `shop=pet` (gärna `pet=dog`), `amenity=veterinary`, `shop=pet_grooming` och `amenity=dog_wash`.
- Egna tydliga pixelikoner används för rastgård, butik, veterinär och trim/tvätt. Spelbutik har liten guldfärgad shoppingpåse ovanpå grundikonen.
- Permanenta platser laddas från aktuell kartvy med buffert och cache och kan visas globalt. På låg zoom grupperas de i kluster med antal; tryck zoomar in.
- Informationsfilter finns per POI-typ och är på från början. Spelbutiker och spelsaker kan inte filtreras bort.
- Popup visar tillgängligt namn, adress, öppettid, telefon, webbplats, butikstatus och avstånd. `Vägbeskrivning` öppnar extern kartapp.

## Adminläge

- Admin tilldelas serverstyrt per Supabase-användar-ID/roll. Ingen hemlig kod i appen.
- Admin väljer tydligt mellan normalt spel och adminläge. Adminläget har synlig banner och påverkar aldrig eget saldo, statistik, livstidssamling eller flockar.
- Att testa `Ta benet` eller en hög ger bara lokal förhandsvisning och tar inte bort världsobjektet. Borttagning är en separat bekräftad handling.
- Redigeringsläge krävs. Arbetsflöde: tryck kartposition, välj objekttyp, välj ben-/högnivå, förhandsvisa, placera. Befintligt objekt kan flyttas, ändras eller tas bort.
- Admin varnas för vatten, byggnad eller avstånd från väg men får välja `Placera ändå`. Admin behöver inte vara fysiskt där och kan söka adress/plats/koordinater utan att GPS förfalskas.
- Admin kan med obligatorisk orsak ge/ta ben utan negativt saldo, ge/ta butiksföremål, återställa olämpliga namn och stänga av/återaktivera spelare. Allt loggas. Dessa åtgärder ändrar inte statistik eller flockbonus.

## Menyer och aktionsprioritet

- Huvudmeny: Profil, Bensamling, Min utrustning, Mina flockar, Mitt hem, Inställningar och Adminläge endast för admin.
- Inställningar: Promenadläge med kort förklaring, skall, vibration, informations-POI-filter, logga ut och radera konto.
- Nederknappar visas samtidigt vid behov i ordning: `Ta benet`, `Gräv upp jordhög`, `Besök butik`, `Besök hemmet`. Benet behöver inte tas först.

## Tekniska kvalitetskrav

- Pengar, föremål, gruppbelöning, cooldowns, lotteri, flockroller och adminrättigheter valideras atomärt på servern med RLS och säkerhetsdefinierade RPC:er.
- Återförsök ska vara idempotenta. Ekonomi och administration har granskningsbar liggare.
- Klienten delas i data-, domän- och UI-lager; inga nya monoliter. Kritisk domänlogik har enhetstester och databasen har SQL-regressionstester.
- Hemligheter lagras aldrig i Git. Release använder externa bygghemligheter/signering.
- Leveransen är versionName `0.400`, versionCode `400`, signerbar APK/AAB, komplett migration och installationsinstruktion.


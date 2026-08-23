# Fix 1

**Status 2026-08-23: implementerad, testad och klar för leverans.**

Implementera ingenting från denna lista förrän Danne uttryckligen säger: **Kör allt i Fix 1**.

## Skattjaktens längd och ordning

- Vald jaktlängd ska motsvara hela rutten: spelarens startposition -> närmaste ledtråd -> närmaste återstående ledtråd -> vidare till sista ledtråden.
- En jakt på 1 km ska bli ungefär 1 km totalt, med en liten tolerans eftersom ledtrådarna måste ligga på gångbara platser.
- Ledtrådarna ska numreras i den faktiska närmaste ruttordningen, inte i slumpmässig ordning.

## Hundfliken och hundinformation

- Under hundens namn i kartans hundflik ska liten text visa hur långt hunden gått av sin totala tillväxtsträcka samt hundens level.
- När hundkortet trycks öppnas en ruta med all information om hunden.
- På både sidan Hundar och den aktiva hundens informationsruta ska varje perk ha en tydlig beskrivning av vad den faktiskt gör och vilket aktuellt bonusvärde den ger.

## Resultat efter skattjakt

- När sista ledtråden tas ska en stor, snygg resultatdialog visas.
- Dialogen ska säga "BRA JOBBAT!" och "Skatten är hittad".
- Alla belöningar, inklusive XP och övriga vinster, ska visas tydligt och snyggt uppställda.
- Dialogen får inte stängas automatiskt eller av misstag. Spelaren måste trycka på **TACK**.

## Bajssystemet

- Alla synliga bajshögar ska gå att plocka upp oavsett vems hund som skapade dem.
- Ingen felaktig väntetid får finnas efter att högen blivit synlig.
- Ett lyckat tryck ska omedelbart ge XP och ta bort högen för samtliga spelare.
- Ett tydligt felmeddelande ska bara visas när högen redan tagits/försvunnit eller spelaren faktiskt är utanför räckvidden.

## Skattjakt efter paus

- En aktiv jakt och dess ledtrådar ska fortsätta fungera efter flera timmars paus, appstängning eller omstart.
- Varje ledtråd ska kontrolleras mot spelarens aktuella GPS-position när den tas. Jaktens ursprungliga GPS-position får inte behöva vara aktuell.
- Om en ledtråd inte kan tas ska verklig orsak visas, exempelvis avstånd, GPS-noggrannhet eller redan tagen ledtråd.

## GPS, positioner och räckvidd

- Hela spelet ska använda samma aktuella GPS-fix och samma tydliga regler för ben, bajs, jordhögar, skattjaktsledtrådar och spelare på kartan.
- Telefonens färskaste användbara position ska skickas med eller synkas omedelbart före varje serverkontrollerad interaktion. Ingen hämtning får bero på en gammal `player_presence` som råkar ligga kvar på servern.
- GPS-fixar ska bedömas efter både ålder och noggrannhet. En äldre eller sämre fix får inte skriva över en nyare och bättre fix.
- Tillåt en rimlig noggrannhetsmarginal vid räckviddskontroller, med ett tydligt max, så att normal GPS-drift inte gör föremål omöjliga att ta. Klient och server ska räkna på samma sätt.
- Om spelaren ser ett föremål som nära nog på kartan ska servern normalt också godkänna det. Knapparnas lokala 25/30-metersgränser får inte motsäga serverns räckvidd inklusive GPS-osäkerhet.
- När GPS-signalen tillfälligt är svag ska appen försöka få en färsk högprecisionsfix under en kort stund i stället för att direkt misslyckas. Under tiden ska spelaren se att positionen uppdateras.
- Ben som inte går att ta ska ge verklig orsak: redan taget/försvunnet, utanför räckvidd, för gammal position, otillräcklig GPS-noggrannhet, anslutningsfel eller serverfel. Det generella meddelandet "det går inte" ska inte användas när orsaken är känd.
- Samma felorsaker och återhämtningsförsök ska gälla för skattjaktsledtrådar, både ensam och i jaktlag.
- Spelarpositioner på kartan ska uppdateras tillräckligt ofta och tåla tillfälligt avbruten realtime-anslutning. Polling ska vara en fungerande reserv och en spelare bredvid ska inte försvinna på grund av en onödigt kort eller osynkad närvarotidsgräns.
- Kartan ska markera när en annan spelares position är gammal i stället för att utan förklaring visa en missvisande position eller dölja spelaren direkt.
- Positionsuppladdning, hämtning och skattjakt ska fungera korrekt efter bakgrundsläge, appstängning och återstart utan att en gammal sessionsposition används som aktuell.
- Lägg till tester för GPS-drift, gammal position, dålig noggrannhet, förbättrad efterföljande fix, två spelare bredvid varandra, benhämtning samt ledtrådar ensam och i jaktlag.

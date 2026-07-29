package se.frasse.bonequest

import android.content.Intent
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import se.frasse.bonequest.walking.WalkingPreferences
import se.frasse.bonequest.walking.WalkingServiceController

enum class GamePanel { PROFILE, COLLECTION, EQUIPMENT, FLOCKS, HOME, SETTINGS, ADMIN, SHOP }

private val PanelDark=Color(0xFF151B1D)
private val PanelGold=Color(0xFFE2AA3D)
private val PanelCream=Color(0xFFFFE5B0)
private val PanelTeal=Color(0xFF168D8A)

@Composable fun GameMenu(
    profile:SessionBootstrap,onClose:()->Unit,onOpen:(GamePanel)->Unit,onQuit:()->Unit
) {
    Surface(Modifier.fillMaxSize(),color=Color(0xF7171B1D)) {
        Row(Modifier.statusBarsPadding().navigationBarsPadding()) {
            Column(Modifier.width(104.dp).fillMaxHeight().background(Color(0xFF111719)).padding(top=18.dp),horizontalAlignment=Alignment.CenterHorizontally) {
                Text("FRASSE",color=PanelGold,fontWeight=FontWeight.Black,fontSize=17.sp)
                Spacer(Modifier.height(18.dp))
                MenuTile("🐾","Profil") { onOpen(GamePanel.PROFILE) }
                MenuTile("🦴","Ben") { onOpen(GamePanel.COLLECTION) }
                MenuTile("🎒","Utrustning") { onOpen(GamePanel.EQUIPMENT) }
                MenuTile("🐕","Flock") { onOpen(GamePanel.FLOCKS) }
                MenuTile("🏠","Hem") { onOpen(GamePanel.HOME) }
                MenuTile("⚙","Inställningar") { onOpen(GamePanel.SETTINGS) }
                if(profile.isAdmin) MenuTile("★","Admin") { onOpen(GamePanel.ADMIN) }
            }
            Column(Modifier.weight(1f).fillMaxHeight().padding(18.dp)) {
                Row(verticalAlignment=Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) { Text(profile.displayName,color=PanelGold,fontSize=27.sp,fontWeight=FontWeight.Black);Text("${profile.boneCount} ben",color=PanelCream) }
                    TextButton(onClick=onClose){Text("STÄNG")}
                }
                HorizontalDivider(color=PanelGold.copy(alpha=.6f));Spacer(Modifier.height(18.dp))
                Text("Frasse’s Bone Quest",fontSize=22.sp,fontWeight=FontWeight.Bold,color=PanelCream)
                Text("Välj en sida i menyn.",color=PanelCream.copy(alpha=.7f))
                Spacer(Modifier.weight(1f));TextButton(onClick=onQuit){Text("STÄNG APPEN")}
            }
        }
    }
}

@Composable private fun MenuTile(icon:String,label:String,onClick:()->Unit) {
    Column(Modifier.fillMaxWidth().clickable(onClick=onClick).padding(vertical=10.dp),horizontalAlignment=Alignment.CenterHorizontally) {
        Text(icon,fontSize=25.sp);Text(label,color=PanelCream,fontSize=11.sp,textAlign=TextAlign.Center)
    }
}

@Composable fun GamePanelScreen(
    panel:GamePanel,profile:SessionBootstrap,api:GameApiRepository,shopPoi:MapPoi?=null,
    poiSettings:PoiSettings=PoiSettings(),onPoiSettings:(PoiSettings)->Unit={},
    onAdminMapMode:()->Unit={},
    onClose:()->Unit,onBalance:(Long)->Unit,onProfile:(SessionBootstrap)->Unit
) {
    Surface(Modifier.fillMaxSize(),color=PanelDark) {
        Column(Modifier.statusBarsPadding().navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().height(58.dp).background(Color(0xFF101719)).padding(horizontal=14.dp),verticalAlignment=Alignment.CenterVertically) {
                TextButton(onClick=onClose){Text("‹ TILLBAKA")};Text(panelTitle(panel),Modifier.weight(1f),color=PanelGold,fontWeight=FontWeight.Black,fontSize=21.sp,textAlign=TextAlign.Center)
                Text("${profile.boneCount} 🦴",color=PanelCream,fontWeight=FontWeight.Bold)
            }
            HorizontalDivider(color=PanelGold)
            Box(Modifier.fillMaxSize().padding(14.dp)) {
                when(panel) {
                    GamePanel.PROFILE -> ProfilePanel(profile,api,onProfile)
                    GamePanel.COLLECTION -> CollectionPanel(api)
                    GamePanel.EQUIPMENT -> EquipmentPanel(api,onProfile)
                    GamePanel.FLOCKS -> FlocksPanel(api,onBalance)
                    GamePanel.HOME -> HomePanel(profile,api,onBalance,onProfile)
                    GamePanel.SETTINGS -> SettingsPanel(profile,api,poiSettings,onPoiSettings,onProfile)
                    GamePanel.SHOP -> ShopPanel(profile,api,shopPoi,onBalance)
                    GamePanel.ADMIN -> AdminPanel(api,onAdminMapMode)
                }
            }
        }
    }
}

private fun panelTitle(p:GamePanel)=when(p){
    GamePanel.PROFILE->"MIN PROFIL";GamePanel.COLLECTION->"BENSAMLING";GamePanel.EQUIPMENT->"MIN UTRUSTNING";
    GamePanel.FLOCKS->"MINA FLOCKAR";GamePanel.HOME->"MITT HEM";GamePanel.SETTINGS->"INSTÄLLNINGAR";
    GamePanel.ADMIN->"ADMINLÄGE";GamePanel.SHOP->"BUTIK"
}

@Composable private fun ProfilePanel(profile:SessionBootstrap,api:GameApiRepository,onProfile:(SessionBootstrap)->Unit) {
    val scope=rememberCoroutineScope();var edit by remember{mutableStateOf(false)};var name by remember{mutableStateOf(profile.displayName)};var message by remember{mutableStateOf<String?>(null)}
    LazyColumn(verticalArrangement=Arrangement.spacedBy(12.dp)) {
        item { StatCard("Spelarnamn",profile.displayName);StatCard("Medlem sedan",profile.createdAt.take(10));StatCard("Bensaldo",profile.boneCount.toString());StatCard("Promenerat","%.2f km".format(profile.totalMeters/1000.0));StatCard("Ben hittade",profile.totalBones.toString());StatCard("Jordhögar",profile.totalPiles.toString());StatCard("Aktiv markör",profile.activeMarkerId) }
        item { Button(onClick={edit=!edit},modifier=Modifier.fillMaxWidth()){Text("ÄNDRA NAMN (24 H COOLDOWN)")} }
        if(edit) item { OutlinedTextField(name,{name=it.take(20)},Modifier.fillMaxWidth(),singleLine=true);Button(enabled=GameNameRules.isValidPlayerName(name),onClick={scope.launch{runCatching{api.changeName(name);api.bootstrap()}.onSuccess{onProfile(it);edit=false}.onFailure{message="Namnet kunde inte ändras ännu"}}}){Text("SPARA")}}
        message?.let { item { Text(it,color=PanelGold) } }
    }
}

@Composable private fun StatCard(label:String,value:String) { Row(Modifier.fillMaxWidth().padding(vertical=7.dp)){Text(label,Modifier.weight(1f),color=PanelCream.copy(alpha=.7f));Text(value,color=PanelCream,fontWeight=FontWeight.Bold)} }

@Composable private fun CollectionPanel(api:GameApiRepository) {
    var rows by remember{mutableStateOf<List<BoneCollectionRow>>(emptyList())};var loading by remember{mutableStateOf(true)}
    LaunchedEffect(Unit){runCatching{api.collection()}.onSuccess{rows=it};loading=false}
    if(loading) Box(Modifier.fillMaxSize(),contentAlignment=Alignment.Center){CircularProgressIndicator(color=PanelGold)} else LazyColumn(verticalArrangement=Arrangement.spacedBy(8.dp)) {
        items((0..11).toList()){type->
            val count=rows.firstOrNull{it.boneType==type}?.lifetimeCount?:0
            Row(Modifier.fillMaxWidth().background(Color(0xFF20282A),RoundedCornerShape(5.dp)).padding(10.dp),verticalAlignment=Alignment.CenterVertically){
                Image(painterResource(boneDrawable(type)),null,Modifier.size(58.dp),contentScale=ContentScale.Fit)
                Column(Modifier.weight(1f).padding(start=10.dp)){Text(if(count>0) BONE_NAMES[type] else "Okänt ben",color=PanelCream,fontWeight=FontWeight.Bold);Text("Värde ${BONE_VALUES[type]}",color=PanelGold)}
                Text(if(count>0) count.toString() else "?",fontSize=22.sp,color=PanelCream,fontWeight=FontWeight.Black)
            }
        }
    }
}
private fun boneDrawable(type:Int)=intArrayOf(R.drawable.bone_01,R.drawable.bone_02,R.drawable.bone_03,R.drawable.bone_04,R.drawable.bone_05,R.drawable.bone_06,R.drawable.bone_07,R.drawable.bone_08,R.drawable.bone_09,R.drawable.bone_10,R.drawable.bone_11,R.drawable.bone_12)[type.coerceIn(0,11)]

@Composable private fun EquipmentPanel(api:GameApiRepository,onProfile:(SessionBootstrap)->Unit) {
    val scope=rememberCoroutineScope();var items by remember{mutableStateOf<List<ShopItem>>(emptyList())};var busy by remember{mutableStateOf(false)}
    fun reload(){scope.launch{items=runCatching{api.catalog()}.getOrDefault(emptyList()).filter{it.owned}}}
    LaunchedEffect(Unit){reload()}
    LazyColumn(verticalArrangement=Arrangement.spacedBy(8.dp)){items(items){item->Row(Modifier.fillMaxWidth().background(Color(0xFF20282A)).clickable(enabled=!busy&&!item.equipped){busy=true;scope.launch{runCatching{api.equip(item.itemId)};onProfile(api.bootstrap());reload();busy=false}}.padding(13.dp)){Text(item.nameSv,Modifier.weight(1f),color=PanelCream);Text(if(item.equipped)"UTRUSTAD" else "VÄLJ",color=if(item.equipped)PanelTeal else PanelGold,fontWeight=FontWeight.Bold)}}}
}

@Composable private fun LegacyHomePanel(profile:SessionBootstrap,api:GameApiRepository,onBalance:(Long)->Unit,onProfile:(SessionBootstrap)->Unit) {
    val scope=rememberCoroutineScope();var result by remember{mutableStateOf("Automaten kan användas inom 50 meter från hemmet.")};var spinning by remember{mutableStateOf(false)}
    Column(verticalArrangement=Arrangement.spacedBy(13.dp)) {
        Text(if(profile.homeLat==null)"Du har inte valt hem ännu." else "Ditt hem är sparat.",color=PanelCream,fontSize=18.sp)
        Button(onClick={scope.launch{runCatching{api.setHome()}.onSuccess{result="Hemmet är sparat. Du kan flytta det igen om 24 timmar.";onProfile(api.bootstrap())}.onFailure{result="Hemmet kunde inte flyttas: kontrollera GPS och cooldown."}}},modifier=Modifier.fillMaxWidth()){Text("SÄTT MITT HEM HÄR")}
        HorizontalDivider();Text("FRASSES HEMMAAUTOMAT",color=PanelGold,fontWeight=FontWeight.Black,fontSize=19.sp)
        Text(result,color=PanelCream)
        Row(horizontalArrangement=Arrangement.spacedBy(7.dp)){listOf(1,2,5,10).forEach{stake->Button(enabled=!spinning,onClick={spinning=true;scope.launch{runCatching{api.spinHome(stake)}.onSuccess{result=if(it.payout==0)"Ingen vinst den här gången." else "Vinst! ${it.payout} ben (${it.multiplier}×)";onBalance(it.balance)}.onFailure{result="Automaten kan bara användas hemma med bra GPS."};delay(5000);spinning=false}}){Text("$stake")}}}
        if(spinning) LinearProgressIndicator(Modifier.fillMaxWidth(),color=PanelGold)
    }
}

@Composable private fun HomePanel(profile:SessionBootstrap,api:GameApiRepository,onBalance:(Long)->Unit,onProfile:(SessionBootstrap)->Unit){
    val scope=rememberCoroutineScope();var message by remember{mutableStateOf("Automaten kan användas inom 50 meter från hemmet.")};var pending by remember{mutableStateOf<SlotResult?>(null)};var revealed by remember{mutableStateOf(true)};var error by remember{mutableStateOf(false)}
    fun reveal(){pending?.let{r->message=if(r.payout==0)"Ingen vinst den här gången." else "Vinst! ${r.payout} ben (${r.multiplier}×)";onBalance(r.balance)};revealed=true;pending=null}
    LaunchedEffect(pending?.spinId){if(pending!=null){delay(5000);reveal()}}
    Column(verticalArrangement=Arrangement.spacedBy(13.dp)){
        Text(if(profile.homeLat==null)"Du har inte valt hem ännu." else "Ditt hem är sparat och syns med en husikon på kartan.",color=PanelCream,fontSize=18.sp)
        Button(enabled=pending==null,onClick={scope.launch{runCatching{api.setHome()}.onSuccess{message="Hemmet sparades. Nästa flytt är möjlig om 24 timmar.";onProfile(api.bootstrap())}.onFailure{message="Hemmet kunde inte flyttas. Kontrollera GPS och cooldown."}}},modifier=Modifier.fillMaxWidth()){Text("SÄTT MITT HEM HÄR")}
        HorizontalDivider();Text("FRASSES HEMMAAUTOMAT",color=PanelGold,fontWeight=FontWeight.Black,fontSize=20.sp);Text(message,color=if(error)Color(0xFFFF6B5D) else PanelCream)
        if(pending==null)Row(horizontalArrangement=Arrangement.spacedBy(7.dp)){listOf(1,2,5,10).forEach{stake->Button(onClick={scope.launch{error=false;runCatching{api.spinHome(stake)}.onSuccess{pending=it;revealed=false;message="🐾 Automaten snurrar…"}.onFailure{error=true;message="Automaten kräver att du är hemma, har bra GPS och tillräckligt med ben."}}}){Text("$stake")}}}
        else Column(horizontalAlignment=Alignment.CenterHorizontally){LinearProgressIndicator(Modifier.fillMaxWidth(),color=PanelGold);Spacer(Modifier.height(12.dp));Text("🦴  🐾  🎾  🦴  🐾",fontSize=27.sp);TextButton(onClick={reveal()}){Text("HOPPA ÖVER")}}
    }
}

@Composable private fun ShopPanel(profile:SessionBootstrap,api:GameApiRepository,poi:MapPoi?,onBalance:(Long)->Unit) {
    val scope=rememberCoroutineScope();var catalog by remember{mutableStateOf<List<ShopItem>>(emptyList())};var category by remember{mutableStateOf<String?>(null)};var message by remember{mutableStateOf<String?>(null)};var pendingPurchase by remember{mutableStateOf<ShopItem?>(null)}
    fun reload(){scope.launch{catalog=runCatching{api.catalog()}.getOrDefault(emptyList());if(category==null)category=catalog.firstOrNull()?.subcategory}}
    LaunchedEffect(Unit){reload()}
    Row(Modifier.fillMaxSize()){
        LazyColumn(Modifier.width(112.dp).fillMaxHeight().background(Color(0xFF111719))){items(catalog.map{it.subcategory}.distinct()){cat->Text(cat,Modifier.fillMaxWidth().clickable{category=cat}.padding(10.dp),color=if(category==cat)PanelGold else PanelCream,fontSize=12.sp)}}
        LazyColumn(Modifier.weight(1f).padding(start=10.dp),verticalArrangement=Arrangement.spacedBy(8.dp)){message?.let{item{Text(it,color=PanelGold)}};items(catalog.filter{it.subcategory==category}){item->Column(Modifier.fillMaxWidth().background(if(item.owned)Color.DarkGray else Color(0xFF20282A)).padding(10.dp)){Box(Modifier.size(46.dp).background(rarityColor(item.rarity),RoundedCornerShape(23.dp)),contentAlignment=Alignment.Center){Text(markerGlyph(item.assetName),fontSize=25.sp)};Text(item.nameSv,color=PanelCream,fontWeight=FontWeight.Bold);Text("${item.rarity} • ${item.price} ben",color=if(item.price>profile.boneCount)Color(0xFFFF6961) else PanelGold);Button(enabled=!item.owned&&item.price<=profile.boneCount&&poi!=null,onClick={pendingPurchase=item}){Text(if(item.owned)"ÄGS" else "KÖP")}}}}
    }
    pendingPurchase?.let{item->AlertDialog(onDismissRequest={pendingPurchase=null},title={Text("Köp ${item.nameSv}?")},text={Text("Det kostar ${item.price} ben. Föremålet utrustas senare under Min utrustning.")},confirmButton={Button(onClick={pendingPurchase=null;scope.launch{runCatching{api.buy(poi!!.poiId,item.itemId)}.onSuccess{onBalance(it.balance);message="${item.nameSv} köpt!";reload()}.onFailure{message="Köpet misslyckades. Du måste vara vid butiken."}}}){Text("KÖP")}},dismissButton={TextButton(onClick={pendingPurchase=null}){Text("AVBRYT")}})}
}
private fun markerGlyph(asset:String)=when{asset.contains("breed")->"🐶";asset.contains("toy")->"🎾";asset.contains("tag")->"🏷";asset.contains("gear")->"🦮";else->"🐾"}
private fun rarityColor(rarity:String)=when(rarity){"mythic"->Color(0xFFE2AA3D);"legendary"->Color(0xFF8D54C7);"epic"->Color(0xFF316DC1);"rare"->Color(0xFF168D8A);else->Color(0xFF3C4547)}

@Composable private fun SettingsPanel(profile:SessionBootstrap,api:GameApiRepository,initialPoiSettings:PoiSettings,onPoiSettings:(PoiSettings)->Unit,onProfile:(SessionBootstrap)->Unit) {
    val context=LocalContext.current;val scope=rememberCoroutineScope();var walking by remember{mutableStateOf(profile.walkingModeEnabled)};var bark by remember{mutableStateOf(profile.barkEnabled)};var vibration by remember{mutableStateOf(profile.vibrationEnabled)};var poiSettings by remember(initialPoiSettings){mutableStateOf(initialPoiSettings)};var saved by remember{mutableStateOf<String?>(null)};var deleting by remember{mutableStateOf(false)};var confirmation by remember{mutableStateOf("")}
    Column(verticalArrangement=Arrangement.spacedBy(13.dp)){
        SettingToggle("Promenadläge","Fortsätter mäta och varnar för ben när skärmen är släckt.",walking){walking=it}
        SettingToggle("Hundskall","Spela ett vänligt voff nära ben.",bark){bark=it}
        SettingToggle("Vibration","Vibrera en gång när du kommer nära ben.",vibration){vibration=it}
        HorizontalDivider(color=PanelGold.copy(alpha=.35f));Text("KARTFILTER",color=PanelGold,fontWeight=FontWeight.Black)
        SettingToggle("Hundrastgårdar","Visa hundrastgårdar på kartan.",poiSettings.showDogParks){poiSettings=poiSettings.copy(showDogParks=it)}
        SettingToggle("Djuraffärer","Visa butiker med djur- och hundsaker.",poiSettings.showPetShops){poiSettings=poiSettings.copy(showPetShops=it)}
        SettingToggle("Veterinärer","Visa veterinärer och djursjukhus.",poiSettings.showVets){poiSettings=poiSettings.copy(showVets=it)}
        SettingToggle("Hundservice","Visa trim, hunddagis och liknande.",poiSettings.showGrooming){poiSettings=poiSettings.copy(showGrooming=it)}
        Button(onClick={scope.launch{runCatching{api.updateSettings(walking,bark,vibration);api.updatePoiSettings(poiSettings)}.onSuccess{WalkingPreferences(context).setEnabled(walking);if(walking)WalkingServiceController.start(context) else WalkingServiceController.stop(context);onPoiSettings(poiSettings);onProfile(api.bootstrap());saved="Inställningarna är sparade."}.onFailure{saved="Kunde inte spara inställningarna."}}},modifier=Modifier.fillMaxWidth()){Text("SPARA")}
        saved?.let{Text(it,color=PanelGold)};Spacer(Modifier.weight(1f));OutlinedButton(onClick={scope.launch{api.signOut()}},modifier=Modifier.fillMaxWidth()){Text("LOGGA UT")};TextButton(onClick={deleting=true},modifier=Modifier.fillMaxWidth()){Text("RADERA KONTO",color=Color(0xFFFF6B5D))}
    }
    if(deleting) AlertDialog(onDismissRequest={deleting=false},title={Text("Radera konto permanent?")},text={Column{Text("Flockledarskap måste först överföras. Skriv ditt exakta spelarnamn för att bekräfta:");OutlinedTextField(confirmation,{confirmation=it},Modifier.fillMaxWidth())}},confirmButton={Button(enabled=confirmation==profile.displayName,onClick={scope.launch{runCatching{api.deleteAccount(confirmation)}.onSuccess{api.signOut()}.onFailure{saved="Kontot kunde inte raderas. Kontrollera flockledarskap och namnet."};deleting=false}}){Text("RADERA")}},dismissButton={TextButton(onClick={deleting=false}){Text("AVBRYT")}})
}
@Composable private fun SettingToggle(title:String,help:String,value:Boolean,onChange:(Boolean)->Unit){Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){Column(Modifier.weight(1f)){Text(title,color=PanelCream,fontWeight=FontWeight.Bold);Text(help,color=PanelCream.copy(alpha=.65f),fontSize=12.sp)};Switch(value,onChange)}}

@Composable private fun LegacyFlocksPanel(api:GameApiRepository,onBalance:(Long)->Unit) {
    val scope=rememberCoroutineScope();var tab by remember{mutableIntStateOf(0)};var mine by remember{mutableStateOf<List<MyFlock>>(emptyList())};var all by remember{mutableStateOf<List<FlockSummary>>(emptyList())};var selected by remember{mutableStateOf<MyFlock?>(null)};var members by remember{mutableStateOf<List<FlockMember>>(emptyList())};var name by remember{mutableStateOf("")};var message by remember{mutableStateOf<String?>(null)}
    fun reload(){scope.launch{mine=runCatching{api.myFlocks()}.getOrDefault(emptyList());all=runCatching{api.listFlocks()}.getOrDefault(emptyList())}}
    LaunchedEffect(Unit){reload()}
    selected?.let{flock->Column{Text(flock.name,color=PanelGold,fontSize=24.sp,fontWeight=FontWeight.Black);Text("Flockbank: %.1f ben • ${flock.memberCount} medlemmar".format(flock.bankBalance),color=PanelCream);Button(onClick={selected=null}){Text("TILL FLOKKLISTAN")};LazyColumn{items(members){m->Column(Modifier.fillMaxWidth().padding(9.dp)){Text(m.displayName,color=PanelCream,fontWeight=FontWeight.Bold);Text("${roleName(m.role)} • %.2f km • ${m.boneBalance} ben".format(m.totalMeters/1000.0),color=PanelGold,fontSize=12.sp)}}}}};if(selected!=null)return
    Column{TabRow(tab){Tab(tab==0,{tab=0},text={Text("MINA")});Tab(tab==1,{tab=1},text={Text("ALLA")});Tab(tab==2,{tab=2},text={Text("SKAPA")})};message?.let{Text(it,color=PanelGold,modifier=Modifier.padding(8.dp))};when(tab){0->LazyColumn{items(mine){f->Row(Modifier.fillMaxWidth().clickable{selected=f;scope.launch{members=api.members(f.flockId)}}.padding(12.dp)){Text("🐾",fontSize=26.sp);Column(Modifier.padding(start=9.dp)){Text(f.name,color=PanelCream,fontWeight=FontWeight.Bold);Text("${roleName(f.myRole)} • ${f.memberCount} • bank %.1f".format(f.bankBalance),color=PanelGold,fontSize=12.sp)}}}};1->LazyColumn{items(all){f->Row(Modifier.fillMaxWidth().padding(10.dp),verticalAlignment=Alignment.CenterVertically){Text("🐾 ${f.name}",Modifier.weight(1f),color=PanelCream);Text("${f.memberCount}",color=PanelGold);TextButton(enabled=mine.none{it.flockId==f.flockId}&&mine.size<3,onClick={scope.launch{runCatching{api.applyToFlock(f.flockId)}.onSuccess{message="Ansökan skickad"}.onFailure{message="Ansökan kunde inte skickas"}}}){Text("GÅ MED")}}}};else->Column(Modifier.padding(top=15.dp)){Text("Det kostar 500 ben att skapa en flock.",color=PanelCream);OutlinedTextField(name,{name=it.take(24)},Modifier.fillMaxWidth(),label={Text("Unikt flocknamn")});Button(onClick={scope.launch{runCatching{api.createFlock(name)}.onSuccess{message="Flocken skapades!";reload();tab=0}.onFailure{message="Namnet är upptaget, ogiltigt eller saldot för lågt."}}},modifier=Modifier.fillMaxWidth()){Text("SKAPA FLOCK")}}}}
}
@Composable private fun FlocksPanel(api:GameApiRepository,onBalance:(Long)->Unit) {
    val scope=rememberCoroutineScope()
    var mine by remember{mutableStateOf<List<MyFlock>>(emptyList())}
    var publicFlocks by remember{mutableStateOf<List<FlockSummary>>(emptyList())}
    var selected by remember{mutableStateOf<MyFlock?>(null)}
    var members by remember{mutableStateOf<List<FlockMember>>(emptyList())}
    var applications by remember{mutableStateOf<List<FlockApplication>>(emptyList())}
    var ledger by remember{mutableStateOf<List<FlockLedgerEntry>>(emptyList())}
    var tab by remember{mutableIntStateOf(0)}
    var detailTab by remember{mutableIntStateOf(0)}
    var name by remember{mutableStateOf("")}
    var message by remember{mutableStateOf<String?>(null)}
    var confirmDelete by remember{mutableStateOf(false)}

    suspend fun reloadLists(){mine=api.myFlocks();publicFlocks=api.listFlocks()}
    suspend fun reloadDetail(f:MyFlock){
        members=api.members(f.flockId)
        ledger=api.ledger(f.flockId)
        applications=if(f.myRole in listOf("leader","guard")) runCatching{api.applications(f.flockId)}.getOrDefault(emptyList()) else emptyList()
        selected=api.myFlocks().firstOrNull{it.flockId==f.flockId}?:f
    }
    LaunchedEffect(Unit){runCatching{reloadLists()}.onFailure{message="Kunde inte hämta flockarna."}}

    val flock=selected
    if(flock!=null){
        Column {
            Row(verticalAlignment=Alignment.CenterVertically){TextButton(onClick={selected=null}){Text("‹ LISTAN")};Column{Text(flock.name,color=PanelGold,fontSize=23.sp,fontWeight=FontWeight.Black);Text("${roleName(flock.myRole)} • ${flock.memberCount} medlemmar • bank %.1f".format(flock.bankBalance),color=PanelCream,fontSize=12.sp)}}
            TabRow(detailTab){listOf("MEDLEMMAR","ANSÖKNINGAR","BANK","HANTERA").forEachIndexed{i,t->Tab(detailTab==i,{detailTab=i},text={Text(t,fontSize=9.sp)})}}
            message?.let{Text(it,color=PanelGold,modifier=Modifier.padding(8.dp))}
            when(detailTab){
                0->LazyColumn{items(members){m->Column(Modifier.fillMaxWidth().background(Color(0xFF20282A)).padding(10.dp)){Text(m.displayName,color=PanelCream,fontWeight=FontWeight.Bold);Text("${roleName(m.role)} • %.2f km • ${m.boneBalance} ben • ${m.totalBones} hittade • ${m.totalPiles} högar".format(m.totalMeters/1000.0),color=PanelGold,fontSize=11.sp);if(flock.myRole=="leader"&&m.role!="leader")Row{TextButton(onClick={scope.launch{runCatching{api.setGuard(flock.flockId,m.playerId,m.role!="guard")}.onSuccess{reloadDetail(flock)}}}){Text(if(m.role=="guard")"GÖR MEDLEM" else "GÖR VAKT")};TextButton(onClick={scope.launch{runCatching{api.transfer(flock.flockId,m.playerId)}.onSuccess{reloadLists();selected=null}}}){Text("GÖR LEDARE")}};if((flock.myRole=="leader"&&m.role!="leader")||(flock.myRole=="guard"&&m.role=="member"))TextButton(onClick={scope.launch{runCatching{api.kick(flock.flockId,m.playerId)}.onSuccess{reloadDetail(flock)}}}){Text("SPARKA",color=Color(0xFFFF6B5D))}}}}
                1->if(flock.myRole !in listOf("leader","guard"))Box(Modifier.fillMaxSize(),contentAlignment=Alignment.Center){Text("Endast ledare och vakter ser ansökningar.",color=PanelCream)}else LazyColumn{items(applications){a->Row(Modifier.fillMaxWidth().padding(10.dp),verticalAlignment=Alignment.CenterVertically){Text(a.displayName,Modifier.weight(1f),color=PanelCream);TextButton(onClick={scope.launch{runCatching{api.decideApplication(flock.flockId,a.playerId,true)}.onSuccess{reloadDetail(flock)}}}){Text("GODKÄNN")};TextButton(onClick={scope.launch{runCatching{api.decideApplication(flock.flockId,a.playerId,false)}.onSuccess{reloadDetail(flock)}}}){Text("NEKA")}}}}
                2->LazyColumn{item{Text("Flockbank: %.1f ben".format(flock.bankBalance),color=PanelGold,fontSize=20.sp,fontWeight=FontWeight.Bold);Text("10 % bonus från lösa ben. Ditt eget benvärde minskar inte.",color=PanelCream,fontSize=12.sp)};items(ledger){e->Row(Modifier.fillMaxWidth().padding(vertical=7.dp)){Column(Modifier.weight(1f)){Text(e.actorName,color=PanelCream);Text(e.reason,color=PanelCream.copy(alpha=.6f),fontSize=11.sp)};Text("%+.1f".format(e.amount),color=if(e.amount>=0)PanelTeal else Color(0xFFFF6B5D),fontWeight=FontWeight.Bold)}}}
                else->Column(verticalArrangement=Arrangement.spacedBy(9.dp)){if(flock.myRole=="leader"){Text("Byt namn: 500 flockben, 7 dygns cooldown.",color=PanelCream);OutlinedTextField(name,{name=it.take(24)},Modifier.fillMaxWidth(),label={Text("Nytt unikt namn")});Button(onClick={scope.launch{runCatching{api.renameFlock(flock.flockId,name)}.onSuccess{message="Flocken döptes om.";reloadLists();reloadDetail(flock)}.onFailure{message="Namnbytet gick inte. Kontrollera bank, namn och cooldown."}}},modifier=Modifier.fillMaxWidth()){Text("BYT NAMN")};Text("Överför ledarskapet under Medlemmar innan du lämnar.",color=PanelCream,fontSize=12.sp);if(flock.memberCount==1L)TextButton(onClick={confirmDelete=true}){Text("TA BORT TOM FLOCK",color=Color(0xFFFF6B5D))}}else Button(onClick={scope.launch{runCatching{api.leave(flock.flockId)}.onSuccess{selected=null;reloadLists()}}},modifier=Modifier.fillMaxWidth()){Text("LÄMNA FLOCKEN")}}
            }
        }
        if(confirmDelete)AlertDialog(onDismissRequest={confirmDelete=false},title={Text("Ta bort ${flock.name}?")},text={Text("Detta går inte att ångra. Flocken måste bara ha dig som medlem.")},confirmButton={Button(onClick={scope.launch{runCatching{api.deleteFlock(flock.flockId,flock.name)}.onSuccess{selected=null;reloadLists()};confirmDelete=false}}){Text("TA BORT")}},dismissButton={TextButton(onClick={confirmDelete=false}){Text("AVBRYT")}})
        return
    }

    Column {
        TabRow(tab){listOf("MINA","ALLA","SKAPA").forEachIndexed{i,t->Tab(tab==i,{tab=i},text={Text(t)})}}
        message?.let{Text(it,color=PanelGold,modifier=Modifier.padding(8.dp))}
        when(tab){
            0->LazyColumn{items(mine){f->Row(Modifier.fillMaxWidth().clickable{scope.launch{reloadDetail(f)}}.padding(12.dp)){Text("🐾",fontSize=25.sp);Column(Modifier.padding(start=9.dp)){Text(f.name,color=PanelCream,fontWeight=FontWeight.Bold);Text("${roleName(f.myRole)} • ${f.memberCount} • bank %.1f".format(f.bankBalance),color=PanelGold,fontSize=11.sp)}}}}
            1->LazyColumn{items(publicFlocks){f->Row(Modifier.fillMaxWidth().padding(10.dp),verticalAlignment=Alignment.CenterVertically){Text("🐾 ${f.name}",Modifier.weight(1f),color=PanelCream);Text("${f.memberCount}",color=PanelGold);TextButton(enabled=mine.none{it.flockId==f.flockId}&&mine.size<3,onClick={scope.launch{runCatching{api.applyToFlock(f.flockId)}.onSuccess{message="Ansökan skickad."}.onFailure{message="Ansökan kunde inte skickas."}}}){Text("GÅ MED")}}}}
            else->Column(Modifier.padding(top=14.dp),verticalArrangement=Arrangement.spacedBy(9.dp)){Text("Det kostar 500 ben. Du kan vara med i högst tre flockar.",color=PanelCream);OutlinedTextField(name,{name=it.take(24)},Modifier.fillMaxWidth(),label={Text("Unikt flocknamn")});Button(onClick={scope.launch{runCatching{api.createFlock(name)}.onSuccess{message="Flocken skapades!";reloadLists();tab=0}.onFailure{message="Kontrollera namnet, saldot och flockplatserna."}}},modifier=Modifier.fillMaxWidth()){Text("SKAPA FLOCK")}}
        }
    }
}

private fun roleName(role:String)=when(role){"leader"->"Flockledare";"guard"->"Flockvakt";else->"Flockmedlem"}

@Composable private fun AdminPanel(api:GameApiRepository,onMapMode:()->Unit){
    val scope=rememberCoroutineScope();var tab by remember{mutableIntStateOf(0)}
    var search by remember{mutableStateOf("")};var players by remember{mutableStateOf<List<AdminPlayer>>(emptyList())};var selected by remember{mutableStateOf<AdminPlayer?>(null)}
    var amount by remember{mutableStateOf("")};var forcedName by remember{mutableStateOf("")};var itemId by remember{mutableStateOf("")};var reason by remember{mutableStateOf("")}
    var lat by remember{mutableStateOf("")};var lon by remember{mutableStateOf("")};var variant by remember{mutableStateOf("0")};var type by remember{mutableStateOf("bone")}
    var message by remember{mutableStateOf<String?>(null)};var audits by remember{mutableStateOf<List<AdminAudit>>(emptyList())}
    fun find(){scope.launch{players=runCatching{api.adminPlayers(search)}.getOrDefault(emptyList())}}
    Column{
        Text("ADMINLÄGE • ändrar aldrig ditt eget normala spel",color=Color(0xFFFF6B5D),fontWeight=FontWeight.Black)
        Button(onClick=onMapMode,modifier=Modifier.fillMaxWidth()){Text("ÖPPNA ADMINLÄGE PÅ KARTAN")}
        TabRow(tab){listOf("SPELARE","PLACERA","LOGG").forEachIndexed{i,t->Tab(tab==i,{tab=i;if(i==2)scope.launch{audits=runCatching{api.audit()}.getOrDefault(emptyList())}},text={Text(t,fontSize=11.sp)})}}
        message?.let{Text(it,color=PanelGold,modifier=Modifier.padding(7.dp))}
        when(tab){
            0->{
                Row{OutlinedTextField(search,{search=it},Modifier.weight(1f),label={Text("Namn eller UUID")});Button(onClick={find()},modifier=Modifier.padding(start=5.dp)){Text("SÖK")}}
                val p=selected
                if(p==null) LazyColumn{items(players){row->Row(Modifier.fillMaxWidth().clickable{selected=row}.padding(10.dp)){Text(row.displayName,Modifier.weight(1f),color=PanelCream);Text(row.boneCount.toString(),color=PanelGold)}}}
                else LazyColumn(verticalArrangement=Arrangement.spacedBy(5.dp)){item{
                    Text(p.displayName,color=PanelGold,fontSize=20.sp);Text("${p.boneCount} ben • ${if(p.isSuspended)"avstängd" else "aktiv"}",color=PanelCream)
                    OutlinedTextField(amount,{amount=it},Modifier.fillMaxWidth(),label={Text("Ben, t.ex. 100 eller -50")})
                    OutlinedTextField(forcedName,{forcedName=it.take(20)},Modifier.fillMaxWidth(),label={Text("Nytt spelarnamn")})
                    OutlinedTextField(itemId,{itemId=it},Modifier.fillMaxWidth(),label={Text("Föremåls-ID")})
                    OutlinedTextField(reason,{reason=it},Modifier.fillMaxWidth(),label={Text("Obligatorisk orsak")})
                    Row{Button(enabled=reason.length>=3&&amount.toLongOrNull()!=null,onClick={scope.launch{runCatching{api.adminAdjustBones(p.playerId,amount.toLong(),reason)}.onSuccess{message="Saldot ändrades";find()}}}){Text("BEN")};Button(enabled=reason.length>=3,onClick={scope.launch{runCatching{if(p.isSuspended)api.adminUnsuspend(p.playerId,reason) else api.adminSuspend(p.playerId,reason)}.onSuccess{message="Status ändrad";find()}}}){Text(if(p.isSuspended)"AKTIVERA" else "STÄNG AV")}}
                    Button(enabled=reason.length>=3&&GameNameRules.isValidPlayerName(forcedName),onClick={scope.launch{runCatching{api.adminForceName(p.playerId,forcedName,reason)}.onSuccess{message="Namnet ändrades";find()}}}){Text("BYT NAMN")}
                    Row{Button(enabled=reason.length>=3&&itemId.isNotBlank(),onClick={scope.launch{runCatching{api.adminSetItem(p.playerId,itemId,true,reason)}.onSuccess{message="Föremålet gavs"}}}){Text("GE SAK")};Button(enabled=reason.length>=3&&itemId.isNotBlank(),onClick={scope.launch{runCatching{api.adminSetItem(p.playerId,itemId,false,reason)}.onSuccess{message="Föremålet togs bort"}}}){Text("TA SAK")}}
                    TextButton(onClick={selected=null}){Text("TILL SPELARLISTAN")}
                }}
            }
            1->Column(verticalArrangement=Arrangement.spacedBy(7.dp)){Text("Placera var som helst med koordinater. Varningar kan kringgås av admin.",color=PanelCream);Row{listOf("bone","pile").forEach{x->FilterChip(type==x,{type=x},label={Text(if(x=="bone")"BEN" else "HÖG")},modifier=Modifier.padding(end=5.dp))}};OutlinedTextField(lat,{lat=it},Modifier.fillMaxWidth(),label={Text("Latitud")});OutlinedTextField(lon,{lon=it},Modifier.fillMaxWidth(),label={Text("Longitud")});OutlinedTextField(variant,{variant=it},Modifier.fillMaxWidth(),label={Text(if(type=="bone")"Bentyp 0–11" else "Högtyp 0–4")});OutlinedTextField(reason,{reason=it},Modifier.fillMaxWidth(),label={Text("Obligatorisk orsak")});Button(enabled=lat.toDoubleOrNull()!=null&&lon.toDoubleOrNull()!=null&&variant.toIntOrNull()!=null&&reason.length>=3,onClick={scope.launch{runCatching{api.adminPlaceObject(type,lat.toDouble(),lon.toDouble(),variant.toInt(),reason)}.onSuccess{message="Objektet placerades"}.onFailure{message="Placeringen misslyckades"}}},modifier=Modifier.fillMaxWidth()){Text("PLACERA")}}
            else->LazyColumn{items(audits){a->Column(Modifier.fillMaxWidth().padding(8.dp)){Text(a.action,color=PanelGold,fontWeight=FontWeight.Bold);Text(a.reason,color=PanelCream);Text(a.createdAt,color=PanelCream.copy(alpha=.6f),fontSize=11.sp)}}}
        }
    }
}

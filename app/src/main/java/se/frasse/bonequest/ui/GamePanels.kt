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
                    GamePanel.SETTINGS -> SettingsPanel(profile,api,onProfile)
                    GamePanel.SHOP -> ShopPanel(profile,api,shopPoi,onBalance)
                    GamePanel.ADMIN -> AdminPanel(api)
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
        item { StatCard("Spelarnamn",profile.displayName);StatCard("Bensaldo",profile.boneCount.toString());StatCard("Promenerat","%.2f km".format(profile.totalMeters/1000.0));StatCard("Ben hittade",profile.totalBones.toString());StatCard("Jordhögar",profile.totalPiles.toString());StatCard("Aktiv markör",profile.activeMarkerId) }
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

@Composable private fun HomePanel(profile:SessionBootstrap,api:GameApiRepository,onBalance:(Long)->Unit,onProfile:(SessionBootstrap)->Unit) {
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

@Composable private fun ShopPanel(profile:SessionBootstrap,api:GameApiRepository,poi:MapPoi?,onBalance:(Long)->Unit) {
    val scope=rememberCoroutineScope();var catalog by remember{mutableStateOf<List<ShopItem>>(emptyList())};var category by remember{mutableStateOf<String?>(null)};var message by remember{mutableStateOf<String?>(null)}
    fun reload(){scope.launch{catalog=runCatching{api.catalog()}.getOrDefault(emptyList());if(category==null)category=catalog.firstOrNull()?.subcategory}}
    LaunchedEffect(Unit){reload()}
    Row(Modifier.fillMaxSize()){
        LazyColumn(Modifier.width(112.dp).fillMaxHeight().background(Color(0xFF111719))){items(catalog.map{it.subcategory}.distinct()){cat->Text(cat,Modifier.fillMaxWidth().clickable{category=cat}.padding(10.dp),color=if(category==cat)PanelGold else PanelCream,fontSize=12.sp)}}
        LazyColumn(Modifier.weight(1f).padding(start=10.dp),verticalArrangement=Arrangement.spacedBy(8.dp)){message?.let{item{Text(it,color=PanelGold)}};items(catalog.filter{it.subcategory==category}){item->Column(Modifier.fillMaxWidth().background(if(item.owned)Color.DarkGray else Color(0xFF20282A)).padding(10.dp)){Text(item.nameSv,color=PanelCream,fontWeight=FontWeight.Bold);Text("${item.rarity} • ${item.price} ben",color=if(item.price>profile.boneCount)Color(0xFFFF6961) else PanelGold);Button(enabled=!item.owned&&item.price<=profile.boneCount&&poi!=null,onClick={scope.launch{runCatching{api.buy(poi!!.poiId,item.itemId)}.onSuccess{onBalance(it.balance);message="${item.nameSv} köpt!";reload()}.onFailure{message="Köpet misslyckades. Du måste vara vid butiken."}}}){Text(if(item.owned)"ÄGS" else "KÖP")}}}}
    }
}

@Composable private fun SettingsPanel(profile:SessionBootstrap,api:GameApiRepository,onProfile:(SessionBootstrap)->Unit) {
    val context=LocalContext.current;val scope=rememberCoroutineScope();var walking by remember{mutableStateOf(profile.walkingModeEnabled)};var bark by remember{mutableStateOf(profile.barkEnabled)};var vibration by remember{mutableStateOf(profile.vibrationEnabled)};var saved by remember{mutableStateOf<String?>(null)};var deleting by remember{mutableStateOf(false)};var confirmation by remember{mutableStateOf("")}
    Column(verticalArrangement=Arrangement.spacedBy(13.dp)){
        SettingToggle("Promenadläge","Fortsätter mäta och varnar för ben när skärmen är släckt.",walking){walking=it}
        SettingToggle("Hundskall","Spela ett vänligt voff nära ben.",bark){bark=it}
        SettingToggle("Vibration","Vibrera en gång när du kommer nära ben.",vibration){vibration=it}
        Button(onClick={scope.launch{runCatching{api.updateSettings(walking,bark,vibration)}.onSuccess{WalkingPreferences(context).setEnabled(walking);if(walking)WalkingServiceController.start(context) else WalkingServiceController.stop(context);onProfile(api.bootstrap());saved="Inställningarna är sparade."}.onFailure{saved="Kunde inte spara inställningarna."}}},modifier=Modifier.fillMaxWidth()){Text("SPARA")}
        saved?.let{Text(it,color=PanelGold)};Spacer(Modifier.weight(1f));OutlinedButton(onClick={scope.launch{api.signOut()}},modifier=Modifier.fillMaxWidth()){Text("LOGGA UT")};TextButton(onClick={deleting=true},modifier=Modifier.fillMaxWidth()){Text("RADERA KONTO",color=Color(0xFFFF6B5D))}
    }
    if(deleting) AlertDialog(onDismissRequest={deleting=false},title={Text("Radera konto permanent?")},text={Column{Text("Flockledarskap måste först överföras. Skriv ditt exakta spelarnamn för att bekräfta:");OutlinedTextField(confirmation,{confirmation=it},Modifier.fillMaxWidth())}},confirmButton={Button(enabled=confirmation==profile.displayName,onClick={scope.launch{runCatching{api.deleteAccount(confirmation)}.onSuccess{api.signOut()}.onFailure{saved="Kontot kunde inte raderas. Kontrollera flockledarskap och namnet."};deleting=false}}){Text("RADERA")}},dismissButton={TextButton(onClick={deleting=false}){Text("AVBRYT")}})
}
@Composable private fun SettingToggle(title:String,help:String,value:Boolean,onChange:(Boolean)->Unit){Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){Column(Modifier.weight(1f)){Text(title,color=PanelCream,fontWeight=FontWeight.Bold);Text(help,color=PanelCream.copy(alpha=.65f),fontSize=12.sp)};Switch(value,onChange)}}

@Composable private fun FlocksPanel(api:GameApiRepository,onBalance:(Long)->Unit) {
    val scope=rememberCoroutineScope();var tab by remember{mutableIntStateOf(0)};var mine by remember{mutableStateOf<List<MyFlock>>(emptyList())};var all by remember{mutableStateOf<List<FlockSummary>>(emptyList())};var selected by remember{mutableStateOf<MyFlock?>(null)};var members by remember{mutableStateOf<List<FlockMember>>(emptyList())};var name by remember{mutableStateOf("")};var message by remember{mutableStateOf<String?>(null)}
    fun reload(){scope.launch{mine=runCatching{api.myFlocks()}.getOrDefault(emptyList());all=runCatching{api.listFlocks()}.getOrDefault(emptyList())}}
    LaunchedEffect(Unit){reload()}
    selected?.let{flock->Column{Text(flock.name,color=PanelGold,fontSize=24.sp,fontWeight=FontWeight.Black);Text("Flockbank: %.1f ben • ${flock.memberCount} medlemmar".format(flock.bankBalance),color=PanelCream);Button(onClick={selected=null}){Text("TILL FLOKKLISTAN")};LazyColumn{items(members){m->Column(Modifier.fillMaxWidth().padding(9.dp)){Text(m.displayName,color=PanelCream,fontWeight=FontWeight.Bold);Text("${roleName(m.role)} • %.2f km • ${m.boneBalance} ben".format(m.totalMeters/1000.0),color=PanelGold,fontSize=12.sp)}}}}};if(selected!=null)return
    Column{TabRow(tab){Tab(tab==0,{tab=0},text={Text("MINA")});Tab(tab==1,{tab=1},text={Text("ALLA")});Tab(tab==2,{tab=2},text={Text("SKAPA")})};message?.let{Text(it,color=PanelGold,modifier=Modifier.padding(8.dp))};when(tab){0->LazyColumn{items(mine){f->Row(Modifier.fillMaxWidth().clickable{selected=f;scope.launch{members=api.members(f.flockId)}}.padding(12.dp)){Text("🐾",fontSize=26.sp);Column(Modifier.padding(start=9.dp)){Text(f.name,color=PanelCream,fontWeight=FontWeight.Bold);Text("${roleName(f.myRole)} • ${f.memberCount} • bank %.1f".format(f.bankBalance),color=PanelGold,fontSize=12.sp)}}}};1->LazyColumn{items(all){f->Row(Modifier.fillMaxWidth().padding(10.dp),verticalAlignment=Alignment.CenterVertically){Text("🐾 ${f.name}",Modifier.weight(1f),color=PanelCream);Text("${f.memberCount}",color=PanelGold);TextButton(enabled=mine.none{it.flockId==f.flockId}&&mine.size<3,onClick={scope.launch{runCatching{api.applyToFlock(f.flockId)}.onSuccess{message="Ansökan skickad"}.onFailure{message="Ansökan kunde inte skickas"}}}){Text("GÅ MED")}}}};else->Column(Modifier.padding(top=15.dp)){Text("Det kostar 500 ben att skapa en flock.",color=PanelCream);OutlinedTextField(name,{name=it.take(24)},Modifier.fillMaxWidth(),label={Text("Unikt flocknamn")});Button(onClick={scope.launch{runCatching{api.createFlock(name)}.onSuccess{message="Flocken skapades!";reload();tab=0}.onFailure{message="Namnet är upptaget, ogiltigt eller saldot för lågt."}}},modifier=Modifier.fillMaxWidth()){Text("SKAPA FLOCK")}}}}
}
private fun roleName(role:String)=when(role){"leader"->"Flockledare";"guard"->"Flockvakt";else->"Flockmedlem"}

@Composable private fun AdminPanel(api:GameApiRepository){
    val scope=rememberCoroutineScope();var tab by remember{mutableIntStateOf(0)};var search by remember{mutableStateOf("")};var players by remember{mutableStateOf<List<AdminPlayer>>(emptyList())};var selected by remember{mutableStateOf<AdminPlayer?>(null)};var amount by remember{mutableStateOf("")};var reason by remember{mutableStateOf("")};var lat by remember{mutableStateOf("")};var lon by remember{mutableStateOf("")};var variant by remember{mutableStateOf("0")};var type by remember{mutableStateOf("bone")};var message by remember{mutableStateOf<String?>(null)};var audits by remember{mutableStateOf<List<AdminAudit>>(emptyList())}
    fun find(){scope.launch{players=runCatching{api.adminPlayers(search)}.getOrDefault(emptyList())}}
    Column{
        Text("ADMINLÄGE • ändrar aldrig ditt eget normala spel",color=Color(0xFFFF6B5D),fontWeight=FontWeight.Black)
        TabRow(tab){listOf("SPELARE","PLACERA","LOGG").forEachIndexed{i,t->Tab(tab==i,{tab=i;if(i==2)scope.launch{audits=runCatching{api.audit()}.getOrDefault(emptyList())}},text={Text(t,fontSize=11.sp)})}}
        message?.let{Text(it,color=PanelGold,modifier=Modifier.padding(7.dp))}
        when(tab){
            0->Column{Row{OutlinedTextField(search,{search=it},Modifier.weight(1f),label={Text("Namn eller UUID")});Button(onClick={find()},modifier=Modifier.padding(start=5.dp)){Text("SÖK")}};selected?.let{p->Text(p.displayName,color=PanelGold,fontSize=20.sp);Text("${p.boneCount} ben • ${if(p.isSuspended)"avstängd" else "aktiv"}",color=PanelCream);OutlinedTextField(amount,{amount=it},Modifier.fillMaxWidth(),label={Text("Ben, t.ex. 100 eller -50")});OutlinedTextField(reason,{reason=it},Modifier.fillMaxWidth(),label={Text("Obligatorisk orsak")});Row{Button(enabled=reason.length>=3&&amount.toLongOrNull()!=null,onClick={scope.launch{runCatching{api.adminAdjustBones(p.playerId,amount.toLong(),reason)}.onSuccess{message="Saldot ändrades";find()}.onFailure{message="Åtgärden misslyckades"}}}){Text("ÄNDRA BEN")};Button(enabled=reason.length>=3,onClick={scope.launch{runCatching{if(p.isSuspended)api.adminUnsuspend(p.playerId,reason) else api.adminSuspend(p.playerId,reason)}.onSuccess{message="Status ändrad";find()}}},modifier=Modifier.padding(start=5.dp)){Text(if(p.isSuspended)"AKTIVERA" else "STÄNG AV")}}};LazyColumn{items(players){p->Row(Modifier.fillMaxWidth().clickable{selected=p}.padding(10.dp)){Text(p.displayName,Modifier.weight(1f),color=PanelCream);Text(p.boneCount.toString(),color=PanelGold)}}}}
            1->Column(verticalArrangement=Arrangement.spacedBy(7.dp)){Text("Placera var som helst med koordinater. Varningar kan kringgås av admin.",color=PanelCream);Row{listOf("bone","pile").forEach{x->FilterChip(type==x,{type=x},label={Text(if(x=="bone")"BEN" else "HÖG")},modifier=Modifier.padding(end=5.dp))}};OutlinedTextField(lat,{lat=it},Modifier.fillMaxWidth(),label={Text("Latitud")});OutlinedTextField(lon,{lon=it},Modifier.fillMaxWidth(),label={Text("Longitud")});OutlinedTextField(variant,{variant=it},Modifier.fillMaxWidth(),label={Text(if(type=="bone")"Bentyp 0–11" else "Högtyp 0–4")});OutlinedTextField(reason,{reason=it},Modifier.fillMaxWidth(),label={Text("Obligatorisk orsak")});Button(enabled=lat.toDoubleOrNull()!=null&&lon.toDoubleOrNull()!=null&&variant.toIntOrNull()!=null&&reason.length>=3,onClick={scope.launch{runCatching{api.adminPlaceObject(type,lat.toDouble(),lon.toDouble(),variant.toInt(),reason)}.onSuccess{message="Objektet placerades"}.onFailure{message="Placeringen misslyckades"}}},modifier=Modifier.fillMaxWidth()){Text("PLACERA")}}
            else->LazyColumn{items(audits){a->Column(Modifier.fillMaxWidth().padding(8.dp)){Text(a.action,color=PanelGold,fontWeight=FontWeight.Bold);Text(a.reason,color=PanelCream);Text(a.createdAt,color=PanelCream.copy(alpha=.6f),fontSize=11.sp)}}}
        }
    }
}

package se.frasse.bonequest

import androidx.compose.ui.res.stringResource

import android.content.Intent
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as gridItems
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import se.frasse.bonequest.walking.WalkingPreferences
import se.frasse.bonequest.walking.WalkingServiceController

enum class GamePanel { PROFILE, COLLECTION, EQUIPMENT, FLOCKS, HOME, SETTINGS, ADMIN, SHOP }

private val PanelDark=Color(0xFF151B1D)
private val PanelGold=Color(0xFFE2AA3D)
private val PanelCream=Color(0xFFFFE5B0)
private val PanelTeal=Color(0xFF168D8A)

@Composable fun GameMenu(
    profile:SessionBootstrap,api:GameApiRepository,shopPoi:MapPoi?=null,
    poiSettings:PoiSettings=PoiSettings(),onPoiSettings:(PoiSettings)->Unit={},
    serverActionsEnabled:Boolean=true,onAdminMapMode:()->Unit={},onClose:()->Unit,
    onBalance:(Long)->Unit,onProfile:(SessionBootstrap)->Unit,onQuit:()->Unit
) {
    var panel by remember { mutableStateOf(GamePanel.PROFILE) }
    Surface(Modifier.fillMaxSize(),color=Color(0xF7171B1D)) {
        Row(Modifier.statusBarsPadding().navigationBarsPadding()) {
            Column(Modifier.width(112.dp).fillMaxHeight().background(Color(0xFF111719)).padding(top=10.dp),horizontalAlignment=Alignment.CenterHorizontally) {
                Row(Modifier.fillMaxWidth().clickable(onClick=onClose).padding(horizontal=10.dp,vertical=9.dp),verticalAlignment=Alignment.CenterVertically){
                    Text("☰",color=PanelGold,fontWeight=FontWeight.Black,fontSize=26.sp)
                    Text("Stäng",Modifier.padding(start=7.dp),color=PanelCream,fontWeight=FontWeight.Bold,fontSize=12.sp)
                }
                Spacer(Modifier.height(8.dp))
                MenuTile("🐾",stringResource(R.string.menu_profile)) { panel=GamePanel.PROFILE }
                MenuTile("🦴",stringResource(R.string.menu_collection)) { panel=GamePanel.COLLECTION }
                MenuTile("🎒",stringResource(R.string.menu_equipment)) { panel=GamePanel.EQUIPMENT }
                MenuTile("🐕",stringResource(R.string.menu_flocks)) { panel=GamePanel.FLOCKS }
                MenuTile("🏠",stringResource(R.string.menu_home)) { panel=GamePanel.HOME }
                MenuTile(R.drawable.menu_settings_pixel,stringResource(R.string.menu_settings)) { panel=GamePanel.SETTINGS }
                if(profile.isAdmin) MenuTile("★",stringResource(R.string.menu_admin)) { panel=GamePanel.ADMIN }
                Spacer(Modifier.weight(1f))
                Column(Modifier.fillMaxWidth().clickable(onClick=onQuit).padding(vertical=12.dp),horizontalAlignment=Alignment.CenterHorizontally){
                    Image(painterResource(R.drawable.menu_power_pixel),null,Modifier.size(42.dp),contentScale=ContentScale.Fit)
                    Text("Stäng appen",color=PanelCream,fontSize=10.sp,textAlign=TextAlign.Center)
                }
            }
            Column(Modifier.weight(1f).fillMaxHeight().padding(14.dp)) {
                Row(verticalAlignment=Alignment.CenterVertically) {
                    Text(stringResource(panelTitleResource(panel)),Modifier.weight(1f),color=PanelGold,fontSize=22.sp,fontWeight=FontWeight.Black)
                    Text(stringResource(R.string.panel_bone_balance,profile.boneCount),color=PanelCream,fontWeight=FontWeight.Bold)
                }
                HorizontalDivider(color=PanelGold.copy(alpha=.6f));Spacer(Modifier.height(10.dp))
                Box(Modifier.fillMaxSize()){
                    if(!serverActionsEnabled&&panel in setOf(GamePanel.EQUIPMENT,GamePanel.FLOCKS,GamePanel.HOME,GamePanel.ADMIN,GamePanel.SHOP)){
                        Column(Modifier.fillMaxSize(),verticalArrangement=Arrangement.Center,horizontalAlignment=Alignment.CenterHorizontally){Text(stringResource(R.string.ui_text_048),color=Color(0xFFFF6B5D),fontSize=22.sp,fontWeight=FontWeight.Black);Text(stringResource(R.string.ui_text_014),color=PanelCream,textAlign=TextAlign.Center)}
                    } else when(panel){
                        GamePanel.PROFILE->ProfilePanel(profile,api,onProfile){panel=GamePanel.COLLECTION}
                        GamePanel.COLLECTION->CollectionPanel(api)
                        GamePanel.EQUIPMENT->EquipmentPanel(api,onProfile)
                        GamePanel.FLOCKS->FlocksPanel(api,onBalance)
                        GamePanel.HOME->HomePanel(profile,api,onBalance,onProfile)
                        GamePanel.SETTINGS->SettingsPanel(profile,api,poiSettings,onPoiSettings,onProfile)
                        GamePanel.SHOP->ShopPanel(profile,api,shopPoi,onBalance)
                        GamePanel.ADMIN->AdminPanel(api){onAdminMapMode();onClose()}
                    }
                }
            }
        }
    }
}

@Composable private fun MenuTile(icon:String,label:String,onClick:()->Unit) {
    Column(Modifier.fillMaxWidth().clickable(onClick=onClick).padding(vertical=10.dp),horizontalAlignment=Alignment.CenterHorizontally) {
        Text(icon,fontSize=25.sp);Text(label,color=PanelCream,fontSize=11.sp,textAlign=TextAlign.Center)
    }
}

@Composable private fun MenuTile(iconRes:Int,label:String,onClick:()->Unit) {
    Column(Modifier.fillMaxWidth().clickable(onClick=onClick).padding(vertical=8.dp),horizontalAlignment=Alignment.CenterHorizontally) {
        Image(painterResource(iconRes),null,Modifier.size(34.dp),contentScale=ContentScale.Fit)
        Text(label,color=PanelCream,fontSize=11.sp,textAlign=TextAlign.Center)
    }
}

@Composable fun GamePanelScreen(
    panel:GamePanel,profile:SessionBootstrap,api:GameApiRepository,shopPoi:MapPoi?=null,
    poiSettings:PoiSettings=PoiSettings(),onPoiSettings:(PoiSettings)->Unit={},
    serverActionsEnabled:Boolean=true,onAdminMapMode:()->Unit={},
    onNavigate:(GamePanel)->Unit={},onClose:()->Unit,onBalance:(Long)->Unit,onProfile:(SessionBootstrap)->Unit
) {
    Surface(Modifier.fillMaxSize(),color=PanelDark) {
        Column(Modifier.statusBarsPadding().navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().height(58.dp).background(Color(0xFF101719)).padding(horizontal=14.dp),verticalAlignment=Alignment.CenterVertically) {
                TextButton(onClick=onClose){Text(stringResource(R.string.ui_text_087))};Text(stringResource(panelTitleResource(panel)),Modifier.weight(1f),color=PanelGold,fontWeight=FontWeight.Black,fontSize=21.sp,textAlign=TextAlign.Center)
                Text(stringResource(R.string.panel_bone_balance,profile.boneCount),color=PanelCream,fontWeight=FontWeight.Bold)
            }
            HorizontalDivider(color=PanelGold)
            Box(Modifier.fillMaxSize().padding(14.dp)) {
                if(!serverActionsEnabled&&panel in setOf(GamePanel.EQUIPMENT,GamePanel.FLOCKS,GamePanel.HOME,GamePanel.ADMIN,GamePanel.SHOP)){
                    Column(Modifier.fillMaxSize(),verticalArrangement=Arrangement.Center,horizontalAlignment=Alignment.CenterHorizontally){Text(stringResource(R.string.ui_text_048),color=Color(0xFFFF6B5D),fontSize=25.sp,fontWeight=FontWeight.Black);Text(stringResource(R.string.ui_text_014),color=PanelCream,textAlign=TextAlign.Center)}
                    return@Box
                }
                when(panel) {
                    GamePanel.PROFILE -> ProfilePanel(profile,api,onProfile){onNavigate(GamePanel.COLLECTION)}
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

private fun panelTitleResource(p:GamePanel)=when(p){
    GamePanel.PROFILE->R.string.panel_profile;GamePanel.COLLECTION->R.string.panel_collection;GamePanel.EQUIPMENT->R.string.panel_equipment
    GamePanel.FLOCKS->R.string.panel_flocks;GamePanel.HOME->R.string.panel_home;GamePanel.SETTINGS->R.string.panel_settings
    GamePanel.ADMIN->R.string.panel_admin;GamePanel.SHOP->R.string.panel_shop
}

@Composable private fun ProfilePanel(profile:SessionBootstrap,api:GameApiRepository,onProfile:(SessionBootstrap)->Unit,onCollection:()->Unit) {
    val scope=rememberCoroutineScope();var edit by remember{mutableStateOf(false)};var name by remember{mutableStateOf(profile.displayName)};var message by remember{mutableStateOf<String?>(null)}
    var markerName by remember(profile.activeMarkerId){mutableStateOf(humanizeMarkerId(profile.activeMarkerId))}
    LaunchedEffect(profile.activeMarkerId){markerName=runCatching{api.catalog().firstOrNull{it.itemId==profile.activeMarkerId}?.nameSv}.getOrNull()?:humanizeMarkerId(profile.activeMarkerId)}
    LazyColumn(verticalArrangement=Arrangement.spacedBy(12.dp)) {
        item { StatCard(stringResource(R.string.profile_game_name),profile.displayName);StatCard("Level",profile.level.toString());StatCard("XP till nästa level",if(profile.level>=100)"MAX" else "${profile.xpCurrentLevel.toInt()} / ${profile.xpNextLevel.toInt()}");StatCard("XP totalt",profile.xpTotal.toInt().toString());StatCard("XP från ben",profile.xpFromBones.toInt().toString());StatCard("XP från promenader",profile.xpFromWalking.toInt().toString());StatCard("XP från jordhögar",profile.xpFromPiles.toInt().toString());StatCard(stringResource(R.string.profile_member_label),profile.createdAt.take(10));StatCard(stringResource(R.string.profile_balance_label),profile.boneCount.toString());StatCard(stringResource(R.string.profile_walked_label),stringResource(R.string.profile_km_value,profile.totalMeters/1000.0));StatCard(stringResource(R.string.profile_bones_found_label),profile.totalBones.toString());StatCard(stringResource(R.string.profile_piles_label),profile.totalPiles.toString());StatCard(stringResource(R.string.profile_active_marker_label),markerName) }
        item { Button(onClick={edit=!edit},modifier=Modifier.fillMaxWidth()){Text(stringResource(R.string.ui_text_082))} }
        item { OutlinedButton(onClick=onCollection,modifier=Modifier.fillMaxWidth()){Text(stringResource(R.string.ui_text_084))} }
        if(edit) item { OutlinedTextField(name,{name=it.take(20)},Modifier.fillMaxWidth(),singleLine=true);Button(enabled=GameNameRules.isValidPlayerName(name),onClick={scope.launch{runCatching{api.changeName(name);api.bootstrap()}.onSuccess{onProfile(it);edit=false}.onFailure{message=it.message}}}){Text(stringResource(R.string.ui_text_062))}}
        message?.let { item { Text(it,color=PanelGold) } }
    }
}

private fun humanizeMarkerId(id:String)=when(id){
    "marker_default_paw"->"Standardtass";"marker_frasse_mythic"->"Frasse"
    else->id.removePrefix("marker_").replace('_',' ').replaceFirstChar{if(it.isLowerCase())it.titlecase() else it.toString()}
}

@Composable private fun StatCard(label:String,value:String) { Row(Modifier.fillMaxWidth().padding(vertical=7.dp)){Text(label,Modifier.weight(1f),color=PanelCream.copy(alpha=.7f));Text(value,color=PanelCream,fontWeight=FontWeight.Bold)} }

@Composable private fun CollectionPanel(api:GameApiRepository) {
    var rows by remember{mutableStateOf<List<BoneCollectionRow>>(emptyList())};var loading by remember{mutableStateOf(true)}
    LaunchedEffect(Unit){runCatching{api.collection()}.onSuccess{rows=it};loading=false}
    if(loading) Box(Modifier.fillMaxSize(),contentAlignment=Alignment.Center){CircularProgressIndicator(color=PanelGold)} else LazyColumn(verticalArrangement=Arrangement.spacedBy(8.dp)) {
        items((0..11).toList()){type->
            val count=rows.firstOrNull{it.boneType==type}?.lifetimeCount?:0
            Row(Modifier.fillMaxWidth().background(Color(0xFF20282A),RoundedCornerShape(5.dp)).padding(10.dp),verticalAlignment=Alignment.CenterVertically){
                Image(painterResource(boneDrawable(type)),null,Modifier.size(58.dp),contentScale=ContentScale.Fit,colorFilter=if(count>0)null else ColorFilter.tint(Color(0xFF5D6263)))
                Column(Modifier.weight(1f).padding(start=10.dp)){Text(if(count>0) localizedBoneName(LocalContext.current,type) else stringResource(R.string.collection_unknown_bone),color=PanelCream,fontWeight=FontWeight.Bold);Text(stringResource(R.string.collection_value,BONE_VALUES[type]),color=PanelGold)}
                Text(if(count>0) count.toString() else "?",fontSize=22.sp,color=PanelCream,fontWeight=FontWeight.Black)
            }
        }
    }
}
private fun boneDrawable(type:Int)=intArrayOf(R.drawable.bone_01,R.drawable.bone_02,R.drawable.bone_03,R.drawable.bone_04,R.drawable.bone_05,R.drawable.bone_06,R.drawable.bone_07,R.drawable.bone_08,R.drawable.bone_09,R.drawable.bone_10,R.drawable.bone_11,R.drawable.bone_12)[type.coerceIn(0,11)]

@Composable private fun EquipmentPanel(api:GameApiRepository,onProfile:(SessionBootstrap)->Unit) {
    val scope=rememberCoroutineScope();var items by remember{mutableStateOf<List<ShopItem>>(emptyList())};var busy by remember{mutableStateOf(false)};var message by remember{mutableStateOf<String?>(null)}
    fun reload(){scope.launch{items=runCatching{api.catalog()}.getOrDefault(emptyList()).filter{it.owned}}}
    LaunchedEffect(Unit){reload()}
    val context=LocalContext.current
    Column{message?.let{Text(it,color=Color(0xFFFF6B5D),modifier=Modifier.padding(bottom=6.dp))};LazyColumn(verticalArrangement=Arrangement.spacedBy(8.dp)){items(items){item->Row(Modifier.fillMaxWidth().background(Color(0xFF20282A)).clickable(enabled=!busy&&!item.equipped){busy=true;message=null;scope.launch{runCatching{api.equip(item.itemId);api.bootstrap()}.onSuccess{onProfile(it);reload()}.onFailure{message=it.message};busy=false}}.padding(13.dp),verticalAlignment=Alignment.CenterVertically){Image(markerBitmap(context,item.assetName).asImageBitmap(),null,Modifier.size(46.dp));Text(item.nameSv,Modifier.weight(1f).padding(start=10.dp),color=PanelCream);Text(stringResource(if(item.equipped)R.string.equipment_equipped else R.string.equipment_select),color=if(item.equipped)PanelTeal else PanelGold,fontWeight=FontWeight.Bold)}}}}
}

@Composable private fun HomePanel(profile:SessionBootstrap,api:GameApiRepository,onBalance:(Long)->Unit,onProfile:(SessionBootstrap)->Unit){
    val context=LocalContext.current;val scope=rememberCoroutineScope();var message by remember{mutableStateOf(context.getString(R.string.home_slot_intro))};var pending by remember{mutableStateOf<SlotResult?>(null)};var revealed by remember{mutableStateOf(true)};var error by remember{mutableStateOf(false)}
    var reelBone by remember{mutableIntStateOf(0)};var lastWasLoss by remember{mutableStateOf(false)}
    fun reveal(){pending?.let{r->lastWasLoss=r.payout==0;message=if(r.payout==0)context.getString(R.string.slot_loss) else context.getString(R.string.slot_win,r.payout,r.multiplier.toString());onBalance(r.balance)};revealed=true;pending=null}
    LaunchedEffect(pending?.spinId){if(pending!=null){repeat(25){reelBone=(reelBone+1)%12;delay(200)};reveal()}}
    Column(verticalArrangement=Arrangement.spacedBy(13.dp)){
        Text(stringResource(if(profile.homeLat==null)R.string.home_not_set else R.string.home_saved_map),color=PanelCream,fontSize=18.sp)
        Button(enabled=pending==null,onClick={scope.launch{runCatching{api.setHome()}.onSuccess{message=context.getString(R.string.home_saved_cooldown);onProfile(api.bootstrap())}.onFailure{message=context.getString(R.string.home_move_failed)}}},modifier=Modifier.fillMaxWidth()){Text(stringResource(R.string.ui_text_068))}
        HorizontalDivider();Text(stringResource(R.string.ui_text_020),color=PanelGold,fontWeight=FontWeight.Black,fontSize=20.sp);Text(message,color=if(error)Color(0xFFFF6B5D) else PanelCream)
        DogBoneSlotMachine(if(lastWasLoss&&pending==null)-1 else reelBone,"Insats 1 · 2 · 5 · 10",pending!=null)
        Column(Modifier.fillMaxWidth().background(Color(0xFF20282A),RoundedCornerShape(5.dp)).padding(9.dp)){Text("VINSTLISTA",color=PanelGold,fontWeight=FontWeight.Black);Text("Ingen vinst 55%  ·  1× 25%  ·  2× 15%",color=PanelCream,fontSize=11.sp);Text("5× 4%  ·  10× 0,9%  ·  50× 0,1%",color=PanelCream,fontSize=11.sp)}
        if(pending==null)Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(7.dp)){listOf(1,2,5,10).forEach{stake->Button(onClick={scope.launch{error=false;runCatching{api.spinHome(stake)}.onSuccess{pending=it;revealed=false;message=context.getString(R.string.slot_spinning)}.onFailure{error=true;message=context.getString(R.string.slot_unavailable)}}},modifier=Modifier.weight(1f),colors=ButtonDefaults.buttonColors(containerColor=Color(0xFFD0B7FF),contentColor=Color(0xFF21162E))){Text(stake.toString(),color=Color(0xFF21162E),fontWeight=FontWeight.Black)}}}
        else Column(horizontalAlignment=Alignment.CenterHorizontally){LinearProgressIndicator(Modifier.fillMaxWidth(),color=PanelGold);TextButton(onClick={reveal()}){Text(stringResource(R.string.ui_text_030))}}
    }
}

@Composable internal fun DogBoneSlotMachine(boneType:Int,information:String,spinning:Boolean,modifier:Modifier=Modifier){
    BoxWithConstraints(modifier.fillMaxWidth().aspectRatio(1.249f),contentAlignment=Alignment.Center){
        Image(painterResource(R.drawable.dog_slot_machine_pixel),null,Modifier.matchParentSize(),contentScale=ContentScale.Fit)
        Box(
            Modifier.align(Alignment.Center).offset(x=(-1).dp,y=8.dp).fillMaxWidth(.36f).fillMaxHeight(.30f),
            contentAlignment=Alignment.Center
        ){
            if(boneType<0)Column(
                Modifier.background(Color(0xFFE8C47F),RoundedCornerShape(3.dp)).padding(horizontal=12.dp,vertical=7.dp),
                horizontalAlignment=Alignment.CenterHorizontally
            ){
                Text("✕",color=Color(0xFF8A2B26),fontSize=24.sp,fontWeight=FontWeight.Black)
                Text("NITLOTT",color=Color(0xFF5A3322),fontWeight=FontWeight.Black,fontSize=10.sp)
            } else Image(painterResource(boneDrawable(boneType)),null,Modifier.fillMaxSize(.82f),contentScale=ContentScale.Fit)
        }
        Column(Modifier.align(Alignment.BottomCenter).padding(bottom=4.dp),horizontalAlignment=Alignment.CenterHorizontally){
            Text(if(spinning)"RULLAR…" else information,color=PanelCream,fontSize=9.sp,fontWeight=FontWeight.Black,textAlign=TextAlign.Center,maxLines=1)
        }
    }
}

@Composable private fun ShopPanel(profile:SessionBootstrap,api:GameApiRepository,poi:MapPoi?,onBalance:(Long)->Unit) {
    val context=LocalContext.current;val scope=rememberCoroutineScope();var catalog by remember{mutableStateOf<List<ShopItem>>(emptyList())};var category by remember{mutableStateOf<String?>(null)};var message by remember{mutableStateOf<String?>(null)};var pendingPurchase by remember{mutableStateOf<ShopItem?>(null)}
    fun reload(){scope.launch{catalog=runCatching{api.catalog()}.getOrDefault(emptyList());if(category==null)category=catalog.firstOrNull()?.subcategory}}
    LaunchedEffect(Unit){reload()}
    Row(Modifier.fillMaxSize()){
        LazyColumn(Modifier.width(112.dp).fillMaxHeight().background(Color(0xFF111719))){catalog.groupBy{it.mainCategory}.forEach{(main,entries)->item{Text(main.uppercase(),Modifier.padding(horizontal=9.dp,vertical=10.dp),color=PanelGold,fontWeight=FontWeight.Black,fontSize=11.sp)};items(entries.map{it.subcategory}.distinct()){cat->Text(cat,Modifier.fillMaxWidth().clickable{category=cat}.padding(horizontal=10.dp,vertical=8.dp),color=if(category==cat)PanelGold else PanelCream,fontSize=11.sp)}}}
        Column(Modifier.weight(1f).padding(start=10.dp)){message?.let{Text(it,color=PanelGold)};LazyVerticalGrid(columns=GridCells.Adaptive(118.dp),modifier=Modifier.fillMaxSize(),horizontalArrangement=Arrangement.spacedBy(8.dp),verticalArrangement=Arrangement.spacedBy(8.dp)){gridItems(catalog.filter{it.subcategory==category}){item->Column(Modifier.fillMaxWidth().background(if(item.owned)Color.DarkGray else Color(0xFF20282A),RoundedCornerShape(5.dp)).padding(9.dp),horizontalAlignment=Alignment.CenterHorizontally){Image(markerBitmap(context,item.assetName).asImageBitmap(),null,Modifier.size(58.dp));Text(item.nameSv,color=PanelCream,fontWeight=FontWeight.Bold,textAlign=TextAlign.Center,fontSize=12.sp);Text(stringResource(R.string.shop_item_price,item.rarity,item.price),color=if(item.price>profile.boneCount)Color(0xFFFF6961) else PanelGold,textAlign=TextAlign.Center,fontSize=11.sp);Button(enabled=!item.owned&&item.price<=profile.boneCount&&poi!=null,onClick={pendingPurchase=item}){Text(stringResource(if(item.owned)R.string.shop_owned else R.string.shop_buy))}}}}}
    }
    pendingPurchase?.let{item->AlertDialog(onDismissRequest={pendingPurchase=null},title={Text(stringResource(R.string.shop_confirm_title,item.nameSv))},text={Text(stringResource(R.string.shop_confirm_body,item.price))},confirmButton={Button(onClick={pendingPurchase=null;scope.launch{runCatching{api.buy(poi!!.poiId,item.itemId)}.onSuccess{onBalance(it.balance);message=context.getString(R.string.shop_purchase_success,item.nameSv);reload()}.onFailure{message=when{it.message?.contains("SHOP_OUT_OF_RANGE")==true->context.getString(R.string.shop_purchase_failed);it.message?.contains("ACCURATE_LOCATION_REQUIRED")==true->context.getString(R.string.bone_gps_inaccurate);it.message?.contains("INSUFFICIENT_BONES")==true->context.getString(R.string.action_need_bones,item.price.toInt());else->"Köpet misslyckades: ${it.message.orEmpty().lineSequence().firstOrNull().orEmpty()}"}}}}){Text(stringResource(R.string.ui_text_035))}},dismissButton={TextButton(onClick={pendingPurchase=null}){Text(stringResource(R.string.ui_text_006))}})}
}

@Composable private fun SettingsPanel(profile:SessionBootstrap,api:GameApiRepository,initialPoiSettings:PoiSettings,onPoiSettings:(PoiSettings)->Unit,onProfile:(SessionBootstrap)->Unit) {
    val context=LocalContext.current;val scope=rememberCoroutineScope();var walking by remember{mutableStateOf(profile.walkingModeEnabled)};var bark by remember{mutableStateOf(profile.barkEnabled)};var vibration by remember{mutableStateOf(profile.vibrationEnabled)};var poiSettings by remember(initialPoiSettings){mutableStateOf(initialPoiSettings)};var saved by remember{mutableStateOf<String?>(null)};var deleting by remember{mutableStateOf(false)};var confirmation by remember{mutableStateOf("")}
    Column(verticalArrangement=Arrangement.spacedBy(13.dp)){
        SettingToggle(stringResource(R.string.settings_walking_title),stringResource(R.string.settings_walking_help),walking){walking=it}
        SettingToggle(stringResource(R.string.settings_bark_title),stringResource(R.string.settings_bark_help),bark){bark=it}
        SettingToggle(stringResource(R.string.settings_vibration_title),stringResource(R.string.settings_vibration_help),vibration){vibration=it}
        HorizontalDivider(color=PanelGold.copy(alpha=.35f));Text(stringResource(R.string.ui_text_034),color=PanelGold,fontWeight=FontWeight.Black)
        SettingToggle(stringResource(R.string.settings_dog_parks),stringResource(R.string.settings_dog_parks_help),poiSettings.showDogParks){poiSettings=poiSettings.copy(showDogParks=it)}
        SettingToggle(stringResource(R.string.settings_pet_shops),stringResource(R.string.settings_pet_shops_help),poiSettings.showPetShops){poiSettings=poiSettings.copy(showPetShops=it)}
        SettingToggle(stringResource(R.string.settings_vets),stringResource(R.string.settings_vets_help),poiSettings.showVets){poiSettings=poiSettings.copy(showVets=it)}
        SettingToggle(stringResource(R.string.settings_services),stringResource(R.string.settings_services_help),poiSettings.showGrooming){poiSettings=poiSettings.copy(showGrooming=it)}
        Button(onClick={scope.launch{runCatching{api.updateSettings(walking,bark,vibration);api.updatePoiSettings(poiSettings)}.onSuccess{WalkingPreferences(context).apply{setEnabled(walking);setBarkEnabled(bark);setVibrationEnabled(vibration)};if(walking)WalkingServiceController.start(context) else WalkingServiceController.stop(context);onPoiSettings(poiSettings);onProfile(api.bootstrap());saved=context.getString(R.string.settings_saved)}.onFailure{saved=context.getString(R.string.settings_save_failed)}}},modifier=Modifier.fillMaxWidth()){Text(stringResource(R.string.ui_text_062))}
        saved?.let{Text(it,color=PanelGold)};Spacer(Modifier.weight(1f));OutlinedButton(onClick={scope.launch{api.signOut()}},modifier=Modifier.fillMaxWidth()){Text(stringResource(R.string.ui_text_036))};TextButton(onClick={deleting=true},modifier=Modifier.fillMaxWidth()){Text(stringResource(R.string.ui_text_058),color=Color(0xFFFF6B5D))}
    }
    if(deleting) AlertDialog(onDismissRequest={deleting=false},title={Text(stringResource(R.string.ui_text_059))},text={Column{Text(stringResource(R.string.ui_text_022));OutlinedTextField(confirmation,{confirmation=it},Modifier.fillMaxWidth())}},confirmButton={Button(enabled=confirmation==profile.displayName,onClick={scope.launch{runCatching{api.deleteAccount(confirmation)}.onSuccess{api.signOut()}.onFailure{saved=context.getString(R.string.account_delete_failed)};deleting=false}}){Text(stringResource(R.string.ui_text_057))}},dismissButton={TextButton(onClick={deleting=false}){Text(stringResource(R.string.ui_text_006))}})
}
@Composable private fun SettingToggle(title:String,help:String,value:Boolean,onChange:(Boolean)->Unit){Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){Column(Modifier.weight(1f)){Text(title,color=PanelCream,fontWeight=FontWeight.Bold);Text(help,color=PanelCream.copy(alpha=.65f),fontSize=12.sp)};Switch(value,onChange)}}

@Composable private fun FlocksPanel(api:GameApiRepository,onBalance:(Long)->Unit) {
    val scope=rememberCoroutineScope()
    val context=LocalContext.current
    var mine by remember{mutableStateOf<List<MyFlock>>(emptyList())}
    var publicFlocks by remember{mutableStateOf<List<FlockSummary>>(emptyList())}
    var selected by remember{mutableStateOf<MyFlock?>(null)}
    var members by remember{mutableStateOf<List<FlockMember>>(emptyList())}
    var applications by remember{mutableStateOf<List<FlockApplication>>(emptyList())}
    var ledger by remember{mutableStateOf<List<FlockLedgerEntry>>(emptyList())}
    var contributions by remember{mutableStateOf<List<FlockContribution>>(emptyList())}
    var tab by remember{mutableIntStateOf(0)}
    var detailTab by remember{mutableIntStateOf(0)}
    var name by remember{mutableStateOf("")}
    var message by remember{mutableStateOf<String?>(null)}
    var confirmDelete by remember{mutableStateOf(false)}
    var statsMember by remember{mutableStateOf<FlockMember?>(null)}
    var statsRows by remember{mutableStateOf<List<BoneCollectionRow>>(emptyList())}

    suspend fun reloadLists(){mine=api.myFlocks();publicFlocks=api.listFlocks()}
    suspend fun reloadDetail(f:MyFlock){
        members=api.members(f.flockId)
        ledger=api.ledger(f.flockId)
        contributions=runCatching{api.contributionLeaderboard(f.flockId)}.getOrElse{
            ledger.filter{it.amount>0}.groupBy{it.actorName}.map{(actor,entries)->FlockContribution("",actor,entries.sumOf{it.amount}.toLong())}.sortedWith(compareByDescending<FlockContribution>{it.totalContributed}.thenBy{it.displayName.lowercase()})
        }
        applications=if(f.myRole in listOf("leader","guard")) runCatching{api.applications(f.flockId)}.getOrDefault(emptyList()) else emptyList()
        selected=api.myFlocks().firstOrNull{it.flockId==f.flockId}?:f
    }
    LaunchedEffect(Unit){runCatching{reloadLists()}.onFailure{message=context.getString(R.string.flock_load_failed)}}

    val flock=selected
    if(flock!=null){
        Column {
            Row(verticalAlignment=Alignment.CenterVertically){TextButton(onClick={selected=null}){Text(stringResource(R.string.ui_text_086))};Column{Text(flock.name,color=PanelGold,fontSize=23.sp,fontWeight=FontWeight.Black);Text(stringResource(R.string.flock_detail_summary,localizedRoleName(flock.myRole,context),flock.memberCount,flock.bankBalance),color=PanelCream,fontSize=12.sp)}}
            TabRow(detailTab){listOf(R.string.flock_tab_members,R.string.flock_tab_applications,R.string.flock_tab_bank,R.string.flock_tab_manage).forEachIndexed{i,t->Tab(detailTab==i,{detailTab=i},text={Text(stringResource(t),fontSize=9.sp)})}}
            message?.let{Text(it,color=PanelGold,modifier=Modifier.padding(8.dp))}
            if(detailTab==0&&members.isNotEmpty()){
                Text(stringResource(R.string.flock_member_stats_help),color=PanelCream.copy(alpha=.75f),fontSize=11.sp)
                LazyRow(horizontalArrangement=Arrangement.spacedBy(6.dp)){items(members){member->
                    AssistChip(onClick={scope.launch{runCatching{api.flockMemberCollection(flock.flockId,member.playerId)}.onSuccess{statsRows=it;statsMember=member}.onFailure{message=context.getString(R.string.flock_member_stats_failed)}}},label={Text(member.displayName)})
                }}
            }
            when(detailTab){
                0->LazyColumn{items(members){m->Column(Modifier.fillMaxWidth().background(Color(0xFF20282A)).padding(10.dp)){Row(verticalAlignment=Alignment.CenterVertically){Text(m.displayName,Modifier.weight(1f),color=PanelCream,fontWeight=FontWeight.Bold);Text("LEVEL ${m.level}",color=PanelTeal,fontSize=11.sp,fontWeight=FontWeight.Black)};Text(stringResource(R.string.flock_member_summary,localizedRoleName(m.role,context),m.totalMeters/1000.0,m.boneBalance,m.totalBones,m.totalPiles),color=PanelGold,fontSize=11.sp);if(flock.myRole=="leader"&&m.role!="leader")Row{TextButton(onClick={scope.launch{runCatching{api.setGuard(flock.flockId,m.playerId,m.role!="guard")}.onSuccess{reloadDetail(flock)}}}){Text(stringResource(if(m.role=="guard")R.string.flock_make_member else R.string.flock_make_guard))};TextButton(onClick={scope.launch{runCatching{api.transfer(flock.flockId,m.playerId)}.onSuccess{reloadLists();selected=null}}}){Text(stringResource(R.string.ui_text_029))}};if((flock.myRole=="leader"&&m.role!="leader")||(flock.myRole=="guard"&&m.role=="member"))TextButton(onClick={scope.launch{runCatching{api.kick(flock.flockId,m.playerId)}.onSuccess{reloadDetail(flock)}}}){Text(stringResource(R.string.ui_text_063),color=Color(0xFFFF6B5D))}}}}
                1->if(flock.myRole !in listOf("leader","guard"))Box(Modifier.fillMaxSize(),contentAlignment=Alignment.Center){Text(stringResource(R.string.ui_text_018),color=PanelCream)}else LazyColumn{items(applications){a->Row(Modifier.fillMaxWidth().padding(10.dp),verticalAlignment=Alignment.CenterVertically){Text(a.displayName,Modifier.weight(1f),color=PanelCream);TextButton(onClick={scope.launch{runCatching{api.decideApplication(flock.flockId,a.playerId,true)}.onSuccess{reloadDetail(flock)}}}){Text(stringResource(R.string.ui_text_026))};TextButton(onClick={scope.launch{runCatching{api.decideApplication(flock.flockId,a.playerId,false)}.onSuccess{reloadDetail(flock)}}}){Text(stringResource(R.string.ui_text_043))}}}}
                2->{
                    LazyColumn{item{Text(stringResource(R.string.ui_text_021).format(flock.bankBalance),color=PanelGold,fontSize=20.sp,fontWeight=FontWeight.Bold);Text("Medlemmarnas sammanlagda bidrag",color=PanelCream,fontSize=12.sp)};items(contributions){entry->val position=contributions.indexOf(entry)+1;Row(Modifier.fillMaxWidth().padding(vertical=8.dp),verticalAlignment=Alignment.CenterVertically){Text("$position.",Modifier.width(30.dp),color=PanelGold,fontWeight=FontWeight.Black);Text(entry.displayName,Modifier.weight(1f),color=PanelCream,fontWeight=FontWeight.Bold);Text("${entry.totalContributed} ben",color=PanelTeal,fontWeight=FontWeight.Black)}}}
                }
                else->Column(verticalArrangement=Arrangement.spacedBy(9.dp)){if(flock.myRole=="leader"){Text(stringResource(R.string.ui_text_013),color=PanelCream);OutlinedTextField(name,{name=it.take(24)},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.ui_text_047))});Button(onClick={scope.launch{runCatching{api.renameFlock(flock.flockId,name)}.onSuccess{message=context.getString(R.string.flock_renamed);reloadLists();reloadDetail(flock)}.onFailure{message=context.getString(R.string.flock_rename_failed)}}},modifier=Modifier.fillMaxWidth()){Text(stringResource(R.string.ui_text_011))};Text(stringResource(R.string.ui_text_085),color=PanelCream,fontSize=12.sp);if(flock.memberCount==1L)TextButton(onClick={confirmDelete=true}){Text(stringResource(R.string.ui_text_073),color=Color(0xFFFF6B5D))}}else Button(onClick={scope.launch{runCatching{api.leave(flock.flockId)}.onSuccess{selected=null;reloadLists()}}},modifier=Modifier.fillMaxWidth()){Text(stringResource(R.string.ui_text_039))}}
            }
        }
        if(confirmDelete)AlertDialog(onDismissRequest={confirmDelete=false},title={Text(stringResource(R.string.flock_delete_title,flock.name))},text={Text(stringResource(R.string.ui_text_017))},confirmButton={Button(onClick={scope.launch{runCatching{api.deleteFlock(flock.flockId,flock.name)}.onSuccess{selected=null;reloadLists()};confirmDelete=false}}){Text(stringResource(R.string.ui_text_070))}},dismissButton={TextButton(onClick={confirmDelete=false}){Text(stringResource(R.string.ui_text_006))}})
        statsMember?.let{member->AlertDialog(onDismissRequest={statsMember=null},title={Text(member.displayName)},text={LazyColumn(Modifier.heightIn(max=430.dp)){items((0..11).toList()){type->val count=statsRows.firstOrNull{it.boneType==type}?.lifetimeCount?:0;Row(Modifier.fillMaxWidth().padding(vertical=5.dp),verticalAlignment=Alignment.CenterVertically){Image(painterResource(boneDrawable(type)),null,Modifier.size(36.dp),colorFilter=if(count>0)null else ColorFilter.tint(Color(0xFF5D6263)));Text(if(count>0)localizedBoneName(context,type) else stringResource(R.string.collection_unknown_bone),Modifier.weight(1f).padding(start=8.dp),color=PanelCream);Text(count.toString(),color=PanelGold,fontWeight=FontWeight.Bold)}}}},confirmButton={TextButton(onClick={statsMember=null}){Text(stringResource(R.string.ui_text_064))}})}
        return
    }

    Column {
        TabRow(tab){listOf(R.string.flock_tab_mine,R.string.flock_tab_all,R.string.flock_tab_create).forEachIndexed{i,t->Tab(tab==i,{tab=i},text={Text(stringResource(t))})}}
        message?.let{Text(it,color=PanelGold,modifier=Modifier.padding(8.dp))}
        when(tab){
            0->LazyColumn{items(mine){f->Row(Modifier.fillMaxWidth().clickable{scope.launch{reloadDetail(f)}}.padding(12.dp)){Text(flockIconGlyph(f.iconId),fontSize=25.sp);Column(Modifier.padding(start=9.dp)){Text(f.name,color=PanelCream,fontWeight=FontWeight.Bold);Text(stringResource(R.string.flock_list_summary,localizedRoleName(f.myRole,context),f.memberCount,f.bankBalance),color=PanelGold,fontSize=11.sp)}}}}
            1->LazyColumn{items(publicFlocks){f->Row(Modifier.fillMaxWidth().padding(10.dp),verticalAlignment=Alignment.CenterVertically){Text("${flockIconGlyph(f.iconId)} ${f.name}",Modifier.weight(1f),color=PanelCream);Text(f.memberCount.toString(),color=PanelGold);TextButton(enabled=mine.none{it.flockId==f.flockId}&&mine.size<3,onClick={scope.launch{runCatching{api.applyToFlock(f.flockId)}.onSuccess{message=context.getString(R.string.flock_application_sent)}.onFailure{message=context.getString(R.string.flock_application_failed)}}}){Text(stringResource(R.string.ui_text_028))}}}}
            else->Column(Modifier.padding(top=14.dp),verticalArrangement=Arrangement.spacedBy(9.dp)){Text(stringResource(R.string.ui_text_016),color=PanelCream);OutlinedTextField(name,{name=it.take(24)},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.ui_text_078))});Button(onClick={scope.launch{runCatching{api.createFlock(name)}.onSuccess{message=context.getString(R.string.flock_created);reloadLists();tab=0}.onFailure{message=context.getString(R.string.flock_create_failed)}}},modifier=Modifier.fillMaxWidth()){Text(stringResource(R.string.ui_text_061))}}
        }
    }
}

private fun localizedRoleName(role:String,context:android.content.Context)=context.getString(when(role){"leader"->R.string.flock_role_leader;"guard"->R.string.flock_role_guard;else->R.string.flock_role_member})
private fun flockIconGlyph(iconId:String)=when(iconId){"flock_paw_shield"->"🛡️";else->"🐾"}
private fun shortTimestamp(value:String)=runCatching{java.time.Instant.parse(value).atZone(java.time.ZoneId.systemDefault()).format(java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm"))}.getOrDefault(value.take(16))

@Composable private fun AdminPanel(api:GameApiRepository,onMapMode:()->Unit){
    val scope=rememberCoroutineScope();val context=LocalContext.current;var tab by remember{mutableIntStateOf(0)}
    var search by remember{mutableStateOf("")};var players by remember{mutableStateOf<List<AdminPlayer>>(emptyList())};var selected by remember{mutableStateOf<AdminPlayer?>(null)}
    var amount by remember{mutableStateOf("")};var boneMode by remember{mutableStateOf("add")};var xpAmount by remember{mutableStateOf("")};var xpMode by remember{mutableStateOf("add")};var forcedName by remember{mutableStateOf("")};var itemId by remember{mutableStateOf("")};var reason by remember{mutableStateOf("")}
    var playerReason by remember{mutableStateOf("Manuell adminändring")}
    var lat by remember{mutableStateOf("")};var lon by remember{mutableStateOf("")};var variant by remember{mutableStateOf("0")};var type by remember{mutableStateOf("bone")}
    var objectId by remember{mutableStateOf("")};var poiName by remember{mutableStateOf("")};var poiType by remember{mutableStateOf("dog_park")};var poiShop by remember{mutableStateOf(false)}
    var addressSearch by remember{mutableStateOf("")}
    var adminFlockId by remember{mutableStateOf("")};var adminFlockName by remember{mutableStateOf("")}
    var confirmObjectPlacement by remember{mutableStateOf(false)}
    var message by remember{mutableStateOf<String?>(null)};var audits by remember{mutableStateOf<List<AdminAudit>>(emptyList())}
    fun find(){scope.launch{runCatching{api.adminPlayers(search)}.onSuccess{players=it;selected=null;message=if(it.isEmpty())"Inga spelare hittades" else null}.onFailure{message="Spelarsökning misslyckades: ${it.message.orEmpty()}"}}}
    Column{
        Text(stringResource(R.string.ui_text_004),color=Color(0xFFFF6B5D),fontWeight=FontWeight.Black)
        Button(onClick=onMapMode,modifier=Modifier.fillMaxWidth()){Text(stringResource(R.string.ui_text_083))}
        TabRow(tab){listOf(R.string.admin_tab_players,R.string.admin_tab_objects,R.string.admin_tab_places,R.string.admin_tab_flocks,R.string.admin_tab_log).forEachIndexed{i,t->Tab(tab==i,{tab=i;if(i==4)scope.launch{audits=runCatching{api.audit()}.getOrDefault(emptyList())}},text={Text(stringResource(t),fontSize=9.sp)})}}
        message?.let{Text(it,color=PanelGold,modifier=Modifier.padding(7.dp))}
        if(tab==1&&objectId.isNotBlank()){
            OutlinedButton(
                enabled=lat.toDoubleOrNull()!=null&&lon.toDoubleOrNull()!=null&&variant.toIntOrNull()!=null&&reason.length>=3,
                onClick={confirmObjectPlacement=true},modifier=Modifier.fillMaxWidth()
            ){Text(stringResource(R.string.admin_preview_update))}
        }
        when(tab){
            0->{
                Row{OutlinedTextField(search,{search=it},Modifier.weight(1f),label={Text(stringResource(R.string.ui_text_045))});Button(onClick={find()},modifier=Modifier.padding(start=5.dp)){Text(stringResource(R.string.ui_text_069))}}
                val p=selected
                if(p==null) LazyColumn{items(players){row->Row(Modifier.fillMaxWidth().clickable{selected=row}.padding(10.dp)){Text(row.displayName,Modifier.weight(1f),color=PanelCream);Text(row.boneCount.toString(),color=PanelGold)}}}
                else LazyColumn(verticalArrangement=Arrangement.spacedBy(5.dp)){item{
                    Text(p.displayName,color=PanelGold,fontSize=20.sp);Text(stringResource(R.string.admin_player_summary,p.boneCount,stringResource(if(p.isSuspended)R.string.admin_status_suspended else R.string.admin_status_active)),color=PanelCream);Text("Level ${p.level} · ${p.xpTotal.toInt()} XP",color=PanelCream)
                    Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(4.dp)){listOf("add" to "GE BEN","subtract" to "TA BEN","set" to "SÄTT SALDO").forEach{(key,label)->FilterChip(boneMode==key,{boneMode=key},label={Text(label,fontSize=8.sp,maxLines=1)},modifier=Modifier.weight(1f))}}
                    OutlinedTextField(amount,{amount=it.filter{char->char.isDigit()}},Modifier.fillMaxWidth(),label={Text("ANTAL BEN")},supportingText={Text(when(boneMode){"add"->"Lägg till ben på spelarens saldo";"subtract"->"Dra av ben utan att saldot kan bli negativt";else->"Ersätt spelarens nuvarande saldo"})},singleLine=true)
                    OutlinedTextField(forcedName,{forcedName=it.take(20)},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.ui_text_046))})
                    OutlinedTextField(itemId,{itemId=it},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.ui_text_024))})
                    OutlinedTextField(playerReason,{playerReason=it},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.admin_action_reason))},singleLine=true)
                    val requestedBones=amount.toLongOrNull();val boneDelta=requestedBones?.let{when(boneMode){"add"->it;"subtract"->-it;else->it-p.boneCount}}
                    Button(enabled=playerReason.trim().length>=3&&requestedBones!=null&&requestedBones>=0&&boneDelta!=null&&boneDelta!=0L&&p.boneCount+boneDelta>=0,onClick={scope.launch{runCatching{api.adminAdjustBones(p.playerId,boneDelta!!,playerReason.trim())}.onSuccess{newBalance->message="Bensaldot sparades: $newBalance ben";selected=p.copy(boneCount=newBalance);players=players.map{if(it.playerId==p.playerId)it.copy(boneCount=newBalance)else it};amount=""}.onFailure{message="Kunde inte ändra ben: ${it.message.orEmpty()}"}}},modifier=Modifier.fillMaxWidth()){Text("SPARA BENSALDO")}
                    Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(4.dp)){listOf("add" to "GE XP","subtract" to "TA XP","set" to "SÄTT XP").forEach{(key,label)->FilterChip(xpMode==key,{xpMode=key},label={Text(label,fontSize=8.sp,maxLines=1)},modifier=Modifier.weight(1f))}}
                    OutlinedTextField(xpAmount,{xpAmount=it.filter{c->c.isDigit()||c=='.'}},Modifier.fillMaxWidth(),label={Text("XP")},singleLine=true)
                    Button(enabled=playerReason.trim().length>=3&&xpAmount.toDoubleOrNull()!=null,onClick={scope.launch{runCatching{api.adminAdjustXp(p.playerId,xpMode,xpAmount.toDouble(),playerReason.trim())}.onSuccess{r->message="XP sparades: ${r.xpTotal.toInt()} XP · level ${r.level}";selected=p.copy(xpTotal=r.xpTotal,level=r.level);players=players.map{if(it.playerId==p.playerId)it.copy(xpTotal=r.xpTotal,level=r.level)else it};xpAmount=""}.onFailure{message="Kunde inte ändra XP: ${it.message.orEmpty()}"}}},modifier=Modifier.fillMaxWidth()){Text("SPARA XP")}
                    Button(enabled=playerReason.length>=3,onClick={scope.launch{runCatching{if(p.isSuspended)api.adminUnsuspend(p.playerId,playerReason) else api.adminSuspend(p.playerId,playerReason)}.onSuccess{message=context.getString(R.string.admin_status_changed);players=api.adminPlayers(search);selected=players.firstOrNull{it.playerId==p.playerId}}.onFailure{message="Adminåtgärden misslyckades: ${it.message.orEmpty()}"}}},modifier=Modifier.fillMaxWidth()){Text(stringResource(if(p.isSuspended)R.string.admin_activate else R.string.admin_suspend))}
                    Button(enabled=playerReason.length>=3&&GameNameRules.isValidPlayerName(forcedName),onClick={scope.launch{runCatching{api.adminForceName(p.playerId,forcedName,playerReason)}.onSuccess{message=context.getString(R.string.admin_name_changed);players=api.adminPlayers(search);selected=players.firstOrNull{it.playerId==p.playerId}}.onFailure{message="Kunde inte ändra namn: ${it.message.orEmpty()}"}}},modifier=Modifier.fillMaxWidth()){Text(stringResource(R.string.ui_text_011))}
                    Row(horizontalArrangement=Arrangement.spacedBy(6.dp)){Button(enabled=playerReason.length>=3&&itemId.isNotBlank(),onClick={scope.launch{runCatching{api.adminSetItem(p.playerId,itemId,true,playerReason)}.onSuccess{message=context.getString(R.string.admin_item_granted)}.onFailure{message="Kunde inte ge föremålet: ${it.message.orEmpty()}"}}}){Text(stringResource(R.string.ui_text_025))};Button(enabled=playerReason.length>=3&&itemId.isNotBlank(),onClick={scope.launch{runCatching{api.adminSetItem(p.playerId,itemId,false,playerReason)}.onSuccess{message=context.getString(R.string.admin_item_removed)}.onFailure{message="Kunde inte ta bort föremålet: ${it.message.orEmpty()}"}}}){Text(stringResource(R.string.ui_text_074))}}
                    TextButton(onClick={selected=null}){Text(stringResource(R.string.ui_text_076))}
                }}
            }
            1->Column(verticalArrangement=Arrangement.spacedBy(7.dp)){Text(stringResource(R.string.ui_text_056),color=PanelCream);Row{listOf("bone","pile").forEach{x->FilterChip(type==x,{type=x},label={Text(stringResource(if(x=="bone")R.string.admin_bone else R.string.admin_pile))},modifier=Modifier.padding(end=5.dp))}};Row{OutlinedTextField(addressSearch,{addressSearch=it},Modifier.weight(1f),label={Text(stringResource(R.string.ui_text_008))});Button(enabled=addressSearch.isNotBlank(),onClick={scope.launch{val found=withContext(Dispatchers.IO){runCatching{android.location.Geocoder(context).getFromLocationName(addressSearch,1)?.firstOrNull()}.getOrNull()};if(found==null)message=context.getString(R.string.admin_place_not_found) else{lat="%.6f".format(java.util.Locale.US,found.latitude);lon="%.6f".format(java.util.Locale.US,found.longitude);message=context.getString(R.string.admin_place_found)}}}){Text(stringResource(R.string.ui_text_069))}};OutlinedTextField(objectId,{objectId=it},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.ui_text_050))});OutlinedTextField(lat,{lat=it},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.ui_text_037))});OutlinedTextField(lon,{lon=it},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.ui_text_038))});OutlinedTextField(variant,{variant=it},Modifier.fillMaxWidth(),label={Text(stringResource(if(type=="bone")R.string.admin_bone_type_range else R.string.admin_pile_type_range))});OutlinedTextField(reason,{reason=it},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.ui_text_051))});Button(enabled=lat.toDoubleOrNull()!=null&&lon.toDoubleOrNull()!=null&&variant.toIntOrNull()!=null&&reason.length>=3,onClick={confirmObjectPlacement=true},modifier=Modifier.fillMaxWidth()){Text(stringResource(R.string.ui_text_053))};OutlinedButton(enabled=objectId.isNotBlank()&&reason.length>=3,onClick={scope.launch{runCatching{api.adminDeleteWorldObject(objectId,type,reason)}.onSuccess{message=context.getString(R.string.admin_object_removed)}.onFailure{message=context.getString(R.string.admin_object_remove_failed)}}},modifier=Modifier.fillMaxWidth()){Text(stringResource(R.string.ui_text_071))}}
            2->LazyColumn(verticalArrangement=Arrangement.spacedBy(7.dp)){item{Text(stringResource(R.string.ui_text_067),color=PanelCream);OutlinedTextField(objectId,{objectId=it},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.ui_text_054))});OutlinedTextField(poiName,{poiName=it},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.ui_text_044))});Row(Modifier.horizontalScroll(androidx.compose.foundation.rememberScrollState())){listOf("dog_park","pet_shop","veterinary","grooming","dog_wash").forEach{x->FilterChip(poiType==x,{poiType=x},label={Text(stringResource(poiTypeNameResource(x)))},modifier=Modifier.padding(end=4.dp))}};OutlinedTextField(lat,{lat=it},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.ui_text_037))});OutlinedTextField(lon,{lon=it},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.ui_text_038))});SettingToggle(stringResource(R.string.admin_game_shop),stringResource(R.string.admin_game_shop_help),poiShop){poiShop=it};OutlinedTextField(reason,{reason=it},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.ui_text_051))});Button(enabled=lat.toDoubleOrNull()!=null&&lon.toDoubleOrNull()!=null&&reason.length>=3,onClick={scope.launch{runCatching{api.adminUpsertPoi(objectId.ifBlank{null},poiType,poiName,lat.toDouble(),lon.toDouble(),poiShop,reason)}.onSuccess{message=context.getString(R.string.admin_place_saved)}.onFailure{message=context.getString(R.string.admin_place_save_failed)}}},modifier=Modifier.fillMaxWidth()){Text(stringResource(if(objectId.isBlank())R.string.admin_create_place else R.string.admin_update_place))};OutlinedButton(enabled=objectId.isNotBlank()&&reason.length>=3,onClick={scope.launch{runCatching{api.adminDeletePoi(objectId,reason)}.onSuccess{message=context.getString(R.string.admin_place_removed)}.onFailure{message=context.getString(R.string.admin_place_remove_failed)}}},modifier=Modifier.fillMaxWidth()){Text(stringResource(R.string.ui_text_072))}}}
            3->Column(verticalArrangement=Arrangement.spacedBy(8.dp)){Text(stringResource(R.string.admin_flock_help),color=PanelCream);OutlinedTextField(adminFlockId,{adminFlockId=it.trim()},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.admin_flock_id))});OutlinedTextField(adminFlockName,{adminFlockName=it.take(24)},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.admin_new_flock_name))});OutlinedTextField(reason,{reason=it},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.ui_text_051))});Button(enabled=adminFlockId.isNotBlank()&&adminFlockName.length>=3&&reason.length>=3,onClick={scope.launch{runCatching{api.adminForceFlockName(adminFlockId,adminFlockName,reason)}.onSuccess{message=context.getString(R.string.admin_flock_name_changed)}.onFailure{message=context.getString(R.string.admin_flock_name_failed)}}},modifier=Modifier.fillMaxWidth()){Text(stringResource(R.string.ui_text_011))}}
            else->LazyColumn{items(audits){a->Column(Modifier.fillMaxWidth().padding(8.dp)){Text(a.action,color=PanelGold,fontWeight=FontWeight.Bold);Text(a.reason,color=PanelCream);Text(a.createdAt,color=PanelCream.copy(alpha=.6f),fontSize=11.sp)}}}
        }
    }
    if(confirmObjectPlacement)AlertDialog(
        onDismissRequest={confirmObjectPlacement=false},
        title={Text(stringResource(R.string.admin_update_title))},
        text={Text(stringResource(R.string.admin_placement_warning))},
        confirmButton={Button(onClick={confirmObjectPlacement=false;scope.launch{
            runCatching{api.adminPlaceObject(type,lat.toDouble(),lon.toDouble(),variant.toInt(),reason,objectId.ifBlank{null})}
                .onSuccess{message=context.getString(if(objectId.isBlank())R.string.admin_object_created else R.string.admin_object_updated)}
                .onFailure{message=context.getString(if(objectId.isBlank())R.string.admin_object_create_failed else R.string.admin_object_update_failed)}
        }}){Text(stringResource(R.string.admin_place_anyway))}},
        dismissButton={TextButton(onClick={confirmObjectPlacement=false}){Text(stringResource(R.string.ui_text_006))}}
    )
}
private fun poiTypeNameResource(type:String)=when(type){
    "dog_park"->R.string.poi_type_dog_park
    "pet_shop"->R.string.poi_type_pet_shop
    "veterinary"->R.string.poi_type_veterinary
    "grooming"->R.string.poi_type_grooming
    else->R.string.poi_type_dog_wash
}

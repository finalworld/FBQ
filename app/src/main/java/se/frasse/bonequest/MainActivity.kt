package se.frasse.bonequest

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.BitmapFactory
import android.graphics.PointF
import android.graphics.RectF
import android.graphics.Color
import android.graphics.Paint
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.zIndex
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.conflate
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.Style
import org.maplibre.android.style.layers.SymbolLayer
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.expressions.Expression
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.geojson.Feature
import org.maplibre.geojson.FeatureCollection
import org.maplibre.geojson.Point
import java.text.NumberFormat
import java.util.Locale

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        MapLibre.getInstance(this)
        lifecycleScope.launch { SupabaseProvider.handleAuthDeepLink(intent) }
        setContent { FrasseAppRoot() }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        lifecycleScope.launch { SupabaseProvider.handleAuthDeepLink(intent) }
    }
}

@Composable
internal fun GameScreen(profile:SessionBootstrap) {
    val context = LocalContext.current
    val repository = remember { GameRepository(context) }
    val worldRepository = remember { SupabaseProvider.clientOrNull?.let(::WorldRepository) }
    val gameApi = remember { SupabaseProvider.clientOrNull?.let(::GameApiRepository) }
    val tracker = remember { LocationTracker(context) }
    val foregroundDistanceFilter=remember { se.frasse.bonequest.walking.DistanceFilter() }
    val foregroundDistanceQueue=remember { se.frasse.bonequest.walking.DistanceQueue(context) }
    val scope = rememberCoroutineScope()

    var permissionGranted by remember {
        mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED)
    }
    var player by remember { mutableStateOf<GeoPoint?>(null) }
    var bones by remember { mutableStateOf(if (worldRepository==null) repository.loadBones() else emptyList()) }
    var piles by remember { mutableStateOf(if (worldRepository==null) repository.loadPiles() else emptyList()) }
    var mapPois by remember { mutableStateOf(emptyList<MapPoi>()) }
    var nearbyPlayers by remember { mutableStateOf(emptyList<NearbyPlayer>()) }
    var poiSettings by remember { mutableStateOf(PoiSettings()) }
    var boneCount by remember(profile.playerId) { mutableIntStateOf(
        if (worldRepository==null) repository.boneCount()
        else profile.boneCount.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    ) }
    var loadingBones by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<String?>("Väntar på GPS…") }
    var followPlayer by remember { mutableStateOf(true) }
    var selectedBone by remember { mutableStateOf<Bone?>(null) }
    var selectedPile by remember { mutableStateOf<DirtPile?>(null) }
    var selectedPoi by remember { mutableStateOf<MapPoi?>(null) }
    var pendingPileReward by remember { mutableStateOf<PileResult?>(null) }
    var menuOpen by remember { mutableStateOf(false) }
    var profileOpen by remember { mutableStateOf(false) }
    var currentProfile by remember(profile.playerId) { mutableStateOf(profile) }
    var activePanel by remember { mutableStateOf<GamePanel?>(null) }
    var collecting by remember { mutableStateOf(false) }
    var lastWorldLoadAt by remember { mutableLongStateOf(0L) }
    var lastWorldCenter by remember { mutableStateOf<GeoPoint?>(null) }
    var gpsHasBeenReady by remember { mutableStateOf(false) }
    var gpsWasInError by remember { mutableStateOf(false) }
    var poiDiscoveryDone by remember { mutableStateOf(false) }
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        permissionGranted = it
        if (!it) status = "GPS-behörighet behövs för att spela"
    }

    LaunchedEffect(Unit) {
        if (!permissionGranted) permissionLauncher.launch(Manifest.permission.ACCESS_FINE_LOCATION)
        gameApi?.let{runCatching{it.poiSettings()}.onSuccess{settings->poiSettings=settings}}
    }

    LaunchedEffect(status, loadingBones) {
        if (status != null && !loadingBones) {
            delay(2_500)
            status = null
        }
    }

    LaunchedEffect(worldRepository) {
        val server = worldRepository ?: return@LaunchedEffect
        val changesJob = launch {
            server.worldChanges.conflate().collect {
                // A collection or RNG shuffle can update many rows in one
                // transaction. Let those events settle, then fetch one fresh
                // authoritative snapshot for the visible world.
                delay(250)
                val center = player ?: return@collect
                runCatching { server.loadNearby(center) }.onSuccess {
                    bones=it.bones; piles=it.piles
                }
            }
        }
        val refreshJob = launch {
            // Realtime normally updates the map immediately. Some Android
            // vendors silently suspend the websocket, so keep a small,
            // invisible safety refresh while the game screen is active.
            while (true) {
                delay(5_000)
                val center = player ?: continue
                runCatching { server.loadNearby(center) }.onSuccess {
                    bones=it.bones; piles=it.piles
                }
                runCatching { server.nearbyPlayers() }.onSuccess { nearbyPlayers=it }
            }
        }
        runCatching { server.subscribe() }
            .onFailure { status = "Liveuppdateringen kunde inte ansluta" }
        try {
            kotlinx.coroutines.awaitCancellation()
        } finally {
            changesJob.cancel()
            refreshJob.cancel()
        }
    }

    DisposableEffect(permissionGranted) {
        if (permissionGranted) {
            tracker.start { location ->
                val point = GeoPoint(location.latitude, location.longitude)
                player = point
                foregroundDistanceFilter.add(se.frasse.bonequest.walking.LocationSample(
                    location.latitude,location.longitude,location.accuracy,
                    location.elapsedRealtimeNanos/1_000_000,location.speed.takeIf{location.hasSpeed()}
                ))?.let { segment ->
                    SupabaseProvider.clientOrNull?.let { client -> scope.launch {
                        val now=System.currentTimeMillis()
                        val batch=se.frasse.bonequest.walking.DistanceBatch(meters=segment.meters.toInt().coerceAtLeast(1),startedAtEpochMillis=now-1_000,endedAtEpochMillis=now)
                        val sync=se.frasse.bonequest.walking.DistanceSyncRepository(client)
                        runCatching { sync.sync(batch) }
                            .onSuccess { currentProfile=currentProfile.copy(totalMeters=currentProfile.totalMeters+segment.meters.toLong());foregroundDistanceQueue.load().forEach{queued->if(runCatching{sync.sync(queued)}.isSuccess)foregroundDistanceQueue.remove(queued.id)} }
                            .onFailure { foregroundDistanceQueue.enqueue(batch) }
                    } }
                }
                if (location.accuracy <= 25) {
                    if (!gpsHasBeenReady || gpsWasInError) status = "GPS klar"
                    gpsHasBeenReady = true
                    gpsWasInError = false
                } else if (!gpsWasInError) {
                    status = "GPS noggrannhet ±${location.accuracy.toInt()} m"
                    gpsWasInError = true
                }
                if (worldRepository!=null) {
                    val needsReload=lastWorldCenter?.let {
                        distanceMeters(it.latitude,it.longitude,point.latitude,point.longitude)>100
                    } ?: true
                    scope.launch {
                        runCatching { worldRepository.updatePresence(
                            point,location.accuracy,location.bearing,location.speed.takeIf { location.hasSpeed() }
                        ) }.isSuccess
                        if(location.accuracy<=30&&!poiDiscoveryDone&&gameApi!=null){
                            poiDiscoveryDone=true
                            runCatching{OverpassClient.discoverDogPois(point)}.onSuccess{found->
                                if(found.isNotEmpty())runCatching{gameApi.syncDiscoveredPois(found)}
                            }.onFailure{poiDiscoveryDone=false}
                        }
                        if (needsReload && System.currentTimeMillis()-lastWorldLoadAt>5_000) {
                            loadingBones=true
                            runCatching { worldRepository.loadNearby(point) }
                                .onSuccess { snapshot ->
                                    bones=snapshot.bones; piles=snapshot.piles
                                    lastWorldCenter=point; lastWorldLoadAt=System.currentTimeMillis()
                                }
                                .onFailure { status="Kunde inte hämta spelvärlden" }
                            loadingBones=false
                        }
                    }
                    return@start
                }
                val nearbyBoneCount = bones.count {
                    distanceMeters(point.latitude, point.longitude, it.latitude, it.longitude) <= 3_000.0
                }
                if ((!repository.generatedNear(point) || nearbyBoneCount < 20) && !loadingBones) {
                    loadingBones = true
                    scope.launch {
                        runCatching { OverpassClient.generateBones(point) }
                            .onSuccess { generated ->
                                if (generated.isNotEmpty()) {
                                    bones = (bones + generated).distinctBy { it.id }
                                    repository.saveBones(bones)
                                    if (piles.isEmpty()) {
                                        piles = generated.filterIndexed { index, _ -> index % 6 == 0 }.mapIndexed { index, b ->
                                            DirtPile("pile-${b.id}", b.latitude, b.longitude, 10 + (index % 5) * 10, index % 5)
                                        }
                                        repository.savePiles(piles)
                                    }
                                    repository.markGenerated(point)
                                    status = "${generated.size} ben placerade på stigar"
                                } else status = "Inga tydliga gångstigar hittades här"
                            }
                            .onFailure { status = "Kunde inte hämta stigar – försök igen senare" }
                        loadingBones = false
                    }
                }
            }
        }
        onDispose { tracker.stop() }
    }

    val nearBone = remember(player, bones) {
        val p = player ?: return@remember null
        bones.minByOrNull { distanceMeters(p.latitude, p.longitude, it.latitude, it.longitude) }
            ?.takeIf { distanceMeters(p.latitude, p.longitude, it.latitude, it.longitude) <= 25.0 }
    }
    val nearPile = remember(player,piles) {
        val p=player?:return@remember null
        piles.minByOrNull { distanceMeters(p.latitude,p.longitude,it.latitude,it.longitude) }
            ?.takeIf { distanceMeters(p.latitude,p.longitude,it.latitude,it.longitude)<=25.0 }
    }
    val nearShop = remember(player,mapPois) {
        val p=player?:return@remember null
        mapPois.filter { it.hasGameShop }.minByOrNull { distanceMeters(p.latitude,p.longitude,it.latitude,it.longitude) }
            ?.takeIf { distanceMeters(p.latitude,p.longitude,it.latitude,it.longitude)<=50.0 }
    }
    val atHome = remember(player,currentProfile.homeLat,currentProfile.homeLon) {
        val p=player;val lat=currentProfile.homeLat;val lon=currentProfile.homeLon
        p!=null&&lat!=null&&lon!=null&&distanceMeters(p.latitude,p.longitude,lat,lon)<=50.0
    }
    LaunchedEffect(nearBone) { selectedBone = nearBone }
    LaunchedEffect(nearBone?.id) {
        if(nearBone!=null&&!currentProfile.walkingModeEnabled){
            if(currentProfile.vibrationEnabled) context.getSystemService(android.os.Vibrator::class.java)
                ?.vibrate(android.os.VibrationEffect.createOneShot(350,android.os.VibrationEffect.DEFAULT_AMPLITUDE))
            if(currentProfile.barkEnabled) android.media.ToneGenerator(android.media.AudioManager.STREAM_NOTIFICATION,75).also { tone->
                tone.startTone(android.media.ToneGenerator.TONE_PROP_BEEP2,220);delay(260);tone.release()
            }
        }
    }
    LaunchedEffect(pendingPileReward?.claimId){
        val reward=pendingPileReward?:return@LaunchedEffect
        delay(3000)
        status="Jordhögen gav +${reward.rewardValue} ben${if(reward.isDouble)" • DUBBELVINST!" else ""}"
        pendingPileReward=null
    }

    MaterialTheme(colorScheme = darkColorScheme()) {
        Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color(0xFF08131B))) {
            GameMap(
                player = player,
                bones = bones,
                piles = piles,
                pois = mapPois.filter{poi->poi.hasGameShop||when(poi.poiType){"dog_park"->poiSettings.showDogParks;"pet_shop"->poiSettings.showPetShops;"veterinary"->poiSettings.showVets;else->poiSettings.showGrooming}},
                nearbyPlayers = nearbyPlayers,
                playerMarkerId = currentProfile.activeMarkerId,
                home = currentProfile.homeLat?.let{lat->currentProfile.homeLon?.let{lon->GeoPoint(lat,lon)}},
                followPlayer = followPlayer,
                onManualMove = { followPlayer = false },
                onBoundsChanged = { bounds ->
                    worldRepository?.let { server ->
                        scope.launch {
                            runCatching { server.mapPois(bounds) }
                                .onSuccess { mapPois = it }
                        }
                    }
                },
                onBoneTapped = { bone ->
                    selectedBone = bone
                    val distance = player?.let { p ->
                        distanceMeters(p.latitude, p.longitude, bone.latitude, bone.longitude).toInt()
                    }
                    status = "${BONE_NAMES[bone.type.coerceIn(BONE_NAMES.indices)].uppercase()}  •  VÄRDE ${boneValue(bone.type)}  •  ${distance?.let { "$it M" } ?: "OKÄNT AVSTÅND"}"
                },
                onPlayerTapped = { activePanel = GamePanel.PROFILE },
                onPileTapped = onPileTapped@{ pile ->
                    val p = player
                    val d = if (p == null) 9999.0 else distanceMeters(p.latitude,p.longitude,pile.latitude,pile.longitude)
                    selectedPile=pile
                    status="Jordhög • kostar ${pile.cost} ben • ${d.toInt()} m"
                    return@onPileTapped
                    if (d <= 25.0) {
                        if (worldRepository!=null) scope.launch {
                            runCatching { worldRepository.openPile(pile.id) }.fold(
                                onSuccess = { result ->
                                    boneCount=result.balance.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
                                    piles=piles.filterNot { it.id==pile.id }
                                    status="Jordhögen gav +${result.rewardValue} ben"
                                },onFailure = { status=when {
                                    it.message?.contains("INSUFFICIENT_BONES")==true -> "Du behöver ${pile.cost} ben"
                                    it.message?.contains("PILE_ALREADY_CLAIMED")==true -> "En annan spelare hann före"
                                    else -> "Kunde inte öppna jordhögen"
                                } }
                            )
                        } else {
                            val result = repository.openPile(pile.id)
                            if (result.second == null) status = "Du behöver ${pile.cost} ben"
                            else { piles = result.first; boneCount = repository.boneCount(); status = "Jordhögen gav +${boneValue(result.second!!.type)} ben" }
                        }
                    } else status = "Jordhög • kostar ${pile.cost} ben • ${d.toInt()} m"
                },
                onPoiTapped={selectedPoi=it},
                modifier = Modifier.fillMaxSize()
            )

            TopHud(
                count = boneCount,
                onMenu = { menuOpen = true },
                modifier = Modifier.align(Alignment.TopCenter)
            )

            if (!followPlayer) {
                FloatingActionButton(
                    onClick = { followPlayer = true },
                    modifier = Modifier.align(Alignment.BottomEnd).navigationBarsPadding().padding(18.dp),
                    containerColor = androidx.compose.ui.graphics.Color(0xFF213141)
                ) { Text("◎", fontSize = 28.sp) }
            }

            selectedBone?.let { bone ->
                val p = player
                val distance = if (p == null) Double.MAX_VALUE else distanceMeters(p.latitude, p.longitude, bone.latitude, bone.longitude)
                if (distance <= 25) {
                    Box(
                        modifier = Modifier
                            .align(Alignment.BottomCenter).zIndex(2f)
                            .navigationBarsPadding()
                            .padding(bottom = 22.dp)
                            .widthIn(max=340.dp)
                            .fillMaxWidth(.88f)
                            .height(62.dp)
                            .clickable(enabled = !collecting) {
                                collecting = true
                                val p0 = player
                                scope.launch {
                                    if (worldRepository!=null) {
                                        runCatching { worldRepository.collectNearbyBones() }.fold(
                                            onSuccess = { rewards ->
                                                val reward=rewards.sumOf { it.playerReward }
                                                rewards.lastOrNull()?.let { boneCount=it.playerBalance.coerceAtMost(Int.MAX_VALUE.toLong()).toInt() }
                                                val ids=if (p0==null) emptySet() else bones.filter {
                                                    distanceMeters(p0.latitude,p0.longitude,it.latitude,it.longitude)<=25
                                                }.mapTo(mutableSetOf()) { it.id }
                                                bones=bones.filterNot { it.id in ids }
                                                status=if (rewards.maxOfOrNull { it.rewardedPlayers } ?: 1>1)
                                                    "+$reward ben • flera spelare belönades" else "+$reward ben"
                                            },onFailure = { error ->
                                                status = when {
                                                    error.message?.contains("NO_BONES_IN_RANGE")==true -> "Någon hann ta benet före dig."
                                                    error.message?.contains("ACCURATE_LOCATION_REQUIRED")==true -> "GPS-signalen är inte tillräckligt exakt ännu."
                                                    else -> "Kunde inte ta benet: ${error.message.orEmpty().lineSequence().firstOrNull().orEmpty()}"
                                                }
                                            }
                                        )
                                    } else {
                                        val inRange = if (p0 == null) emptyList() else bones.filter { distanceMeters(p0.latitude,p0.longitude,it.latitude,it.longitude) <= 25.0 }
                                        val result = repository.collectBones(inRange.map { it.id })
                                        delay(450); bones=result.first; boneCount=repository.boneCount()
                                        status=if (result.second>0) "+${result.second} ben" else "Någon hann ta benet före dig."
                                    }
                                    selectedBone = null
                                    collecting = false
                                }
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        ActionButtonContent(
                            iconDrawable=R.drawable.bone_01,
                            label=if (collecting) "SAMLAR…" else "TA BENET",
                            detail="+${boneValue(bone.type)} BEN  •  ${distance.toInt()} M"
                        )
                    }
                }
            }

            val statusText = if (loadingBones) "Letar gångstigar…" else status
            nearPile?.let { pile ->
                val pileOffset=if(nearBone!=null)92.dp else 22.dp
                Box(Modifier.align(Alignment.BottomCenter).zIndex(2f).navigationBarsPadding().padding(bottom=pileOffset)
                    .widthIn(max=340.dp).fillMaxWidth(.88f).height(62.dp)
                    .clickable(enabled=boneCount>=pile.cost&&!collecting){
                        collecting=true;scope.launch{
                            if(worldRepository!=null) runCatching{worldRepository.openPile(pile.id)}.fold(
                                onSuccess={r->boneCount=r.balance.coerceAtMost(Int.MAX_VALUE.toLong()).toInt();currentProfile=currentProfile.copy(boneCount=r.balance,totalPiles=currentProfile.totalPiles+1,totalBones=currentProfile.totalBones+r.quantity);piles=piles.filterNot{it.id==pile.id};pendingPileReward=r;status="🐾 Gräver… snurran väljer ben"},
                                onFailure={status=if(it.message?.contains("PILE_ALREADY_CLAIMED")==true)"En annan spelare hann före" else "Kunde inte gräva upp högen"})
                            collecting=false;selectedPile=null
                        }
                    }) { ActionButtonContent(dirtDrawable(pile.type),if(boneCount>=pile.cost)"GRÄV UPP" else "BEHÖVER ${pile.cost} BEN","KOSTAR ${pile.cost} BEN") }
            }
            nearShop?.let { shop ->
                val index=(if(nearBone!=null)1 else 0)+(if(nearPile!=null)1 else 0)
                Box(Modifier.align(Alignment.BottomCenter).zIndex(2f).navigationBarsPadding().padding(bottom=(22+70*index).dp).widthIn(max=340.dp).fillMaxWidth(.88f).height(62.dp).clickable{activePanel=GamePanel.SHOP}) { ActionButtonContent(R.drawable.poi_pet_shop,"BESÖK BUTIK",shop.name?:"HUNDBUTIK") }
            }
            if(atHome) {
                val index=(if(nearBone!=null)1 else 0)+(if(nearPile!=null)1 else 0)+(if(nearShop!=null)1 else 0)
                Box(Modifier.align(Alignment.BottomCenter).zIndex(2f).navigationBarsPadding().padding(bottom=(22+70*index).dp).widthIn(max=340.dp).fillMaxWidth(.88f).height(62.dp).clickable{activePanel=GamePanel.HOME}) { ActionButtonContent(R.drawable.marker_default_paw,"BESÖK HEMMET","FRASSES HEMMAAUTOMAT") }
            }
            pendingPileReward?.let { reward->
                Surface(Modifier.align(Alignment.Center).padding(24.dp),color=androidx.compose.ui.graphics.Color(0xF21A2022),shape=RoundedCornerShape(8.dp)){
                    Column(Modifier.padding(22.dp),horizontalAlignment=Alignment.CenterHorizontally){Text("JORDFYND",color=androidx.compose.ui.graphics.Color(0xFFFFC85B),fontSize=24.sp,fontWeight=FontWeight.Black);Text("🦴  🐾  🦴  🎾  🦴",fontSize=28.sp);LinearProgressIndicator(Modifier.fillMaxWidth().padding(vertical=12.dp));TextButton(onClick={status="Jordhögen gav +${reward.rewardValue} ben${if(reward.isDouble)" • DUBBELVINST!" else ""}";pendingPileReward=null}){Text("HOPPA ÖVER")}}
                }
            }
            if (statusText != null) {
                Surface(
                    modifier = Modifier.align(Alignment.BottomCenter).navigationBarsPadding()
                        .padding(bottom=if (nearBone==null) 10.dp else 94.dp),
                    color = androidx.compose.ui.graphics.Color(0xF2171A1C),
                    shape = RoundedCornerShape(4.dp)
                ) {
                    Text(
                        statusText,
                        Modifier.padding(horizontal = 15.dp, vertical = 9.dp),
                        color = androidx.compose.ui.graphics.Color(0xFFFFD78D),
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Black
                    )
                }
            }
        }

        if (profileOpen) {
            val st = repository.stats()
            AlertDialog(onDismissRequest={profileOpen=false}, title={Text(st.displayName)}, text={
                Column(verticalArrangement=Arrangement.spacedBy(6.dp)) {
                    Text("Gått: ${"%.2f".format(st.totalKm)} km")
                    Text("Samlade ben: ${st.totalBonesCollected}")
                    Text("Öppnade jordhögar: ${st.totalDirtPilesOpened}")
                    Text("Medlem sedan: ${java.text.SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(java.util.Date(st.memberSince))}")
                }
            }, confirmButton={TextButton(onClick={profileOpen=false}){Text("STÄNG")}})
        }

        if (menuOpen && gameApi == null) {
            AlertDialog(
                onDismissRequest = { menuOpen = false },
                title = { Text("Frasse’s Bone Quest") },
                text = {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Version 0.400")
                        Button(onClick = { menuOpen=false; profileOpen=true }, modifier = Modifier.fillMaxWidth()) { Text("MIN PROFIL") }
                        Text("Serverläge förberett – P2P är helt borttaget.", fontSize = 13.sp)
                        Text("Samlade ben: $boneCount", fontWeight = FontWeight.Bold)
                    }
                },
                confirmButton = {
                    TextButton(onClick = { (context as? Activity)?.finishAffinity() }) { Text("STÄNG APPEN") }
                },
                dismissButton = { TextButton(onClick = { menuOpen = false }) { Text("TILLBAKA") } }
            )
        }
        if (menuOpen && gameApi != null) {
            GameMenu(
                profile=currentProfile.copy(boneCount=boneCount.toLong()),
                onClose={menuOpen=false},onOpen={activePanel=it;menuOpen=false},
                onQuit={(context as? Activity)?.finishAffinity()}
            )
        }
        activePanel?.let { panel ->
            gameApi?.let { api ->
                val nearbyShop=mapPois.firstOrNull { poi -> poi.hasGameShop && player?.let { p ->
                    distanceMeters(p.latitude,p.longitude,poi.latitude,poi.longitude)<=50
                }==true }
                GamePanelScreen(
                    panel=panel,profile=currentProfile.copy(boneCount=boneCount.toLong()),api=api,
                    shopPoi=nearbyShop,poiSettings=poiSettings,onPoiSettings={poiSettings=it},onClose={activePanel=null},
                    onBalance={balance->boneCount=balance.coerceAtMost(Int.MAX_VALUE.toLong()).toInt();currentProfile=currentProfile.copy(boneCount=balance)},
                    onProfile={fresh->currentProfile=fresh;boneCount=fresh.boneCount.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()}
                )
            }
        }
        selectedPoi?.let { poi ->
            val distance=player?.let{distanceMeters(it.latitude,it.longitude,poi.latitude,poi.longitude).toInt()}
            AlertDialog(onDismissRequest={selectedPoi=null},title={Text(poi.name?:poiTypeName(poi.poiType))},text={Column(verticalArrangement=Arrangement.spacedBy(5.dp)){Text(poiTypeName(poi.poiType));poi.address?.let{Text(it)};poi.openingHours?.let{Text("Öppet: $it")};poi.phone?.let{Text("Telefon: $it")};poi.website?.let{Text(it,color=androidx.compose.ui.graphics.Color(0xFF5BC8C5))};Text("${distance?:0} m bort");if(poi.hasGameShop)Text("Här finns en spelbutik.",fontWeight=FontWeight.Bold)}},confirmButton={Button(onClick={val uri=Uri.parse("geo:${poi.latitude},${poi.longitude}?q=${poi.latitude},${poi.longitude}(${Uri.encode(poi.name?:"Hundplats")})");context.startActivity(Intent(Intent.ACTION_VIEW,uri));selectedPoi=null}){Text("VÄGBESKRIVNING")}},dismissButton={TextButton(onClick={selectedPoi=null}){Text("STÄNG")}})
        }
    }
}

@Composable
private fun TopHud(count: Int, onMenu: () -> Unit, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth()) {
        Image(
            painter = painterResource(R.drawable.hud_panel_pixel_v2),
            contentDescription = null,
            modifier = Modifier.matchParentSize(),
            contentScale = ContentScale.FillBounds
        )
        Box(Modifier.statusBarsPadding().fillMaxWidth().height(62.dp)) {
        Row(Modifier.fillMaxSize(),verticalAlignment=Alignment.CenterVertically) {
            Box(
                Modifier.width(64.dp).fillMaxHeight().clickable(onClick=onMenu),
                contentAlignment=Alignment.Center
            ) {
                Column(
                    modifier = Modifier.width(23.dp).height(19.dp),
                    verticalArrangement = Arrangement.SpaceBetween
                ) {
                    repeat(3) {
                        Box(
                            Modifier.fillMaxWidth().height(4.dp)
                                .background(androidx.compose.ui.graphics.Color(0xFFFFE0A0))
                        )
                    }
                }
            }
            Box(Modifier.width(2.dp).fillMaxHeight(.72f).background(androidx.compose.ui.graphics.Color(0xFFC79439)))
            Image(
                painter=painterResource(R.drawable.hud_logo),
                contentDescription="Frasse’s Bone Quest",
                modifier=Modifier.weight(1f).fillMaxHeight().padding(horizontal=10.dp,vertical=8.dp),
                contentScale=ContentScale.Fit
            )
            Text(
                NumberFormat.getIntegerInstance(Locale.forLanguageTag("sv-SE")).format(count),
                modifier=Modifier.widthIn(min=72.dp,max=132.dp).padding(end=5.dp),
                color=androidx.compose.ui.graphics.Color(0xFFFFE8BE),fontWeight=FontWeight.Black,
                fontSize=when { count<1_000_000->21.sp; count<100_000_000->17.sp; else->14.sp },
                maxLines=1,textAlign=TextAlign.End
            )
            Image(
                painter=painterResource(R.drawable.bone_01),contentDescription=null,
                modifier=Modifier.padding(end=8.dp).size(35.dp),contentScale=ContentScale.Fit
            )
        }
        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(2.dp)
            .background(androidx.compose.ui.graphics.Color(0xFFFFC85B)))
        }
    }
}

@Composable
private fun ActionButtonContent(iconDrawable:Int,label:String,detail:String) {
    Box(Modifier.fillMaxSize()) {
        Image(
            painter = painterResource(R.drawable.action_panel_pixel),
            contentDescription = null,
            modifier = Modifier.matchParentSize(),
            contentScale = ContentScale.FillBounds
        )
        Row(Modifier.fillMaxSize(),verticalAlignment=Alignment.CenterVertically) {
            Box(Modifier.width(84.dp).fillMaxHeight(),contentAlignment=Alignment.Center) {
                Image(painterResource(iconDrawable),null,Modifier.size(43.dp),contentScale=ContentScale.Fit)
            }
            Text(
                label,
                Modifier.weight(1f).padding(start=12.dp),
                color=androidx.compose.ui.graphics.Color(0xFFFFD78D),
                fontWeight=FontWeight.Black,fontSize=17.sp,maxLines=1,
                softWrap=false
            )
            Text(
                detail,
                Modifier.weight(1.12f).padding(end=17.dp),
                color=androidx.compose.ui.graphics.Color(0xFFFFD78D),
                fontWeight=FontWeight.Black,fontSize=13.sp,maxLines=1,
                softWrap=false,textAlign=TextAlign.End
            )
        }
    }
}

private fun dirtDrawable(type:Int)=intArrayOf(
    R.drawable.dirt_pile_01,R.drawable.dirt_pile_02,R.drawable.dirt_pile_03,
    R.drawable.dirt_pile_04,R.drawable.dirt_pile_05
)[type.coerceIn(0,4)]

@Composable
private fun GameMap(
    player: GeoPoint?, bones: List<Bone>, piles: List<DirtPile>, pois: List<MapPoi>, nearbyPlayers:List<NearbyPlayer>, playerMarkerId:String,home:GeoPoint?, followPlayer: Boolean,
    onManualMove: () -> Unit, onBoundsChanged: (MapBounds) -> Unit, onBoneTapped: (Bone) -> Unit,
    onPlayerTapped: () -> Unit, onPileTapped: (DirtPile) -> Unit,onPoiTapped:(MapPoi)->Unit, modifier: Modifier
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var map by remember { mutableStateOf<MapLibreMap?>(null) }
    var styleReady by remember { mutableStateOf(false) }
    val latestBones by rememberUpdatedState(bones)
    val latestBoneTap by rememberUpdatedState(onBoneTapped)
    val latestPlayerTap by rememberUpdatedState(onPlayerTapped)
    val latestPileTap by rememberUpdatedState(onPileTapped)
    val latestPiles by rememberUpdatedState(piles)
    val latestPois by rememberUpdatedState(pois)
    val latestPoiTap by rememberUpdatedState(onPoiTapped)
    val latestBoundsChanged by rememberUpdatedState(onBoundsChanged)

    val mapView = remember {
        MapView(context).apply {
            getMapAsync { libreMap ->
                libreMap.cameraPosition = CameraPosition.Builder()
                    .target(LatLng(59.51, 17.63))
                    .zoom(13.0)
                    .build()

                libreMap.setStyle(Style.Builder().fromUri("asset://game_style.json")) { style ->
                    installGameLayers(style, context)
                    map = libreMap
                    styleReady = true
                }

                libreMap.addOnCameraMoveStartedListener { reason ->
                    if (reason == MapLibreMap.OnCameraMoveStartedListener.REASON_API_GESTURE) {
                        onManualMove()
                    }
                }
                libreMap.addOnCameraIdleListener {
                    val bounds = libreMap.projection.visibleRegion.latLngBounds
                    latestBoundsChanged(MapBounds(bounds.latitudeSouth, bounds.longitudeWest, bounds.latitudeNorth, bounds.longitudeEast))
                }

                libreMap.addOnMapClickListener { latLng ->
                    val screenPoint: PointF = libreMap.projection.toScreenLocation(latLng)
                    val hitArea = RectF(
                        screenPoint.x - 28f, screenPoint.y - 28f,
                        screenPoint.x + 28f, screenPoint.y + 28f
                    )
                    val features = libreMap.queryRenderedFeatures(
                        hitArea,
                        *(BONE_LAYER_IDS + PILE_LAYER_IDS + POI_LAYER_IDS + arrayOf(PLAYER_LAYER_ID))
                    )
                    val boneIds = features.mapNotNull {
                        it.properties()?.get(BONE_ID_PROPERTY)?.asString
                    }.toSet()
                    val tappedBone = latestBones
                        .asSequence()
                        .filter { it.id in boneIds }
                        .minByOrNull {
                            distanceMeters(latLng.latitude, latLng.longitude, it.latitude, it.longitude)
                        }
                    if (tappedBone != null) {
                        latestBoneTap(tappedBone); true
                    } else {
                        val pileIds = features.mapNotNull {
                            it.properties()?.get(PILE_ID_PROPERTY)?.asString
                        }.toSet()
                        val tappedPile = latestPiles
                            .asSequence()
                            .filter { it.id in pileIds }
                            .minByOrNull {
                                distanceMeters(latLng.latitude, latLng.longitude, it.latitude, it.longitude)
                            }
                        if (tappedPile != null) { latestPileTap(tappedPile); true }
                        else {
                            val poiIds=features.mapNotNull{it.properties()?.get("poiId")?.asString}.toSet()
                            val tappedPoi=latestPois.firstOrNull{it.poiId in poiIds}
                            if(tappedPoi!=null){latestPoiTap(tappedPoi);true}
                            else if (features.isNotEmpty()) { latestPlayerTap(); true } else false
                        }
                    }
                }
            }
        }
    }

    DisposableEffect(lifecycleOwner, mapView) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> mapView.onStart()
                Lifecycle.Event.ON_RESUME -> mapView.onResume()
                Lifecycle.Event.ON_PAUSE -> mapView.onPause()
                Lifecycle.Event.ON_STOP -> mapView.onStop()
                Lifecycle.Event.ON_DESTROY -> mapView.onDestroy()
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        mapView.onCreate(null)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            mapView.onDestroy()
        }
    }

    androidx.compose.ui.viewinterop.AndroidView(factory = { mapView }, modifier = modifier)

    LaunchedEffect(map, styleReady, player, followPlayer,playerMarkerId) {
        val m = map ?: return@LaunchedEffect
        if (!styleReady) return@LaunchedEffect
        val style = m.style ?: return@LaunchedEffect
        style.addImage(PLAYER_IMAGE_ID,markerBitmap(context,playerMarkerId))
        val source = style.getSourceAs<GeoJsonSource>(PLAYER_SOURCE_ID) ?: return@LaunchedEffect
        source.setGeoJson(playerFeatureCollection(player))

        player?.let { p ->
            if (followPlayer) {
                m.animateCamera(
                    CameraUpdateFactory.newLatLngZoom(LatLng(p.latitude, p.longitude), 16.2),
                    700
                )
            }
        }
    }

    LaunchedEffect(map, styleReady, bones) {
        val m = map ?: return@LaunchedEffect
        if (!styleReady) return@LaunchedEffect
        val style = m.style ?: return@LaunchedEffect
        val source = style.getSourceAs<GeoJsonSource>(BONE_SOURCE_ID) ?: return@LaunchedEffect
        source.setGeoJson(boneFeatureCollection(bones))
    }

    LaunchedEffect(map, styleReady, piles) {
        val m = map ?: return@LaunchedEffect
        if (!styleReady) return@LaunchedEffect
        val source = m.style?.getSourceAs<GeoJsonSource>(PILE_SOURCE_ID) ?: return@LaunchedEffect
        source.setGeoJson(pileFeatureCollection(piles))
    }

    LaunchedEffect(map,styleReady,nearbyPlayers) {
        val source=map?.style?.getSourceAs<GeoJsonSource>(NEARBY_PLAYER_SOURCE_ID)?:return@LaunchedEffect
        source.setGeoJson(nearbyPlayerFeatureCollection(nearbyPlayers))
    }
    LaunchedEffect(map,styleReady,home){map?.style?.getSourceAs<GeoJsonSource>(HOME_SOURCE_ID)?.setGeoJson(playerFeatureCollection(home))}

    LaunchedEffect(map, styleReady, pois) {
        val m = map ?: return@LaunchedEffect
        if (!styleReady) return@LaunchedEffect
        val source = m.style?.getSourceAs<GeoJsonSource>(POI_SOURCE_ID) ?: return@LaunchedEffect
        source.setGeoJson(poiFeatureCollection(pois))
    }
}

private const val PLAYER_SOURCE_ID = "frasse-player-source"
private const val PLAYER_LAYER_ID = "frasse-player-layer"
private const val PLAYER_IMAGE_ID = "frasse-player-image"
private const val NEARBY_PLAYER_SOURCE_ID="frasse-nearby-players-source"
private const val NEARBY_PLAYER_LAYER_ID="frasse-nearby-players-layer"
private val FLOCK_DOT_IMAGE_IDS=arrayOf("frasse-flock-dot-1","frasse-flock-dot-2","frasse-flock-dot-3")
private val FLOCK_DOT_LAYER_IDS=arrayOf("frasse-flock-dot-layer-1","frasse-flock-dot-layer-2","frasse-flock-dot-layer-3")
private const val HOME_SOURCE_ID="frasse-home-source"
private const val HOME_LAYER_ID="frasse-home-layer"
private const val HOME_IMAGE_ID="frasse-home-image"
private const val BONE_SOURCE_ID = "frasse-bones-source"
private const val PILE_SOURCE_ID = "frasse-piles-source"
private const val PILE_ID_PROPERTY = "pileId"
private val PILE_IMAGE_IDS = Array(5) { "frasse-pile-image-${it+1}" }
private val PILE_LAYER_IDS = Array(5) { "frasse-pile-layer-${it+1}" }
private const val BONE_ID_PROPERTY = "boneId"
private const val BONE_TYPE_PROPERTY = "boneType"
private val BONE_IMAGE_IDS = Array(12) { index -> "frasse-bone-image-${index + 1}" }
private val BONE_LAYER_IDS = Array(12) { index -> "frasse-bones-layer-${index + 1}" }
private const val POI_SOURCE_ID = "frasse-pois-source"
private const val POI_TYPE_PROPERTY = "poiType"
private val POI_TYPES = arrayOf("dog_park", "pet_shop", "veterinary", "grooming", "dog_wash")
private val POI_IMAGE_IDS = arrayOf("frasse-poi-dog-park", "frasse-poi-pet-shop", "frasse-poi-veterinary", "frasse-poi-grooming", "frasse-poi-grooming")
private val POI_LAYER_IDS = POI_TYPES.map { "frasse-poi-$it-layer" }.toTypedArray()

private fun installGameLayers(style: Style, context: android.content.Context) {
    style.addImage(PLAYER_IMAGE_ID, defaultMarkerBitmap(context))
    style.addImage(HOME_IMAGE_ID,homeBitmap())
    intArrayOf(Color.rgb(22,141,138),Color.rgb(226,170,61),Color.rgb(80,145,220)).forEachIndexed{i,color->style.addImage(FLOCK_DOT_IMAGE_IDS[i],dotBitmap(color))}

    val boneDrawables = intArrayOf(
        R.drawable.bone_01, R.drawable.bone_02, R.drawable.bone_03,
        R.drawable.bone_04, R.drawable.bone_05, R.drawable.bone_06,
        R.drawable.bone_07, R.drawable.bone_08, R.drawable.bone_09,
        R.drawable.bone_10, R.drawable.bone_11, R.drawable.bone_12
    )
    boneDrawables.forEachIndexed { index, drawableId ->
        BitmapFactory.decodeResource(context.resources, drawableId)?.let { bitmap ->
            style.addImage(BONE_IMAGE_IDS[index], bitmap)
        }
    }

    if (style.getSource(PLAYER_SOURCE_ID) == null) {
        style.addSource(GeoJsonSource(PLAYER_SOURCE_ID, FeatureCollection.fromFeatures(emptyArray<Feature>())))
    }
    if (style.getLayer(PLAYER_LAYER_ID) == null) {
        style.addLayer(
            SymbolLayer(PLAYER_LAYER_ID, PLAYER_SOURCE_ID).withProperties(
                PropertyFactory.iconImage(PLAYER_IMAGE_ID),
                PropertyFactory.iconAllowOverlap(true),
                PropertyFactory.iconIgnorePlacement(true),
                PropertyFactory.iconSize(0.72f)
            )
        )
    }

    if (style.getSource(BONE_SOURCE_ID) == null) {
        style.addSource(GeoJsonSource(BONE_SOURCE_ID, FeatureCollection.fromFeatures(emptyArray<Feature>())))
    }
    BONE_LAYER_IDS.forEachIndexed { index, layerId ->
        if (style.getLayer(layerId) == null) {
            style.addLayerBelow(
                SymbolLayer(layerId, BONE_SOURCE_ID)
                    .withFilter(
                        Expression.eq(
                            Expression.get(BONE_TYPE_PROPERTY),
                            Expression.literal(index)
                        )
                    )
                    .withProperties(
                        PropertyFactory.iconImage(BONE_IMAGE_IDS[index]),
                        PropertyFactory.iconAllowOverlap(true),
                        PropertyFactory.iconIgnorePlacement(true),
                        PropertyFactory.iconSize(0.72f)
                    ),
                PLAYER_LAYER_ID
            )
        }
    }
    val pileDrawables = intArrayOf(R.drawable.dirt_pile_01,R.drawable.dirt_pile_02,R.drawable.dirt_pile_03,R.drawable.dirt_pile_04,R.drawable.dirt_pile_05)
    pileDrawables.forEachIndexed { index, id -> BitmapFactory.decodeResource(context.resources,id)?.let { style.addImage(PILE_IMAGE_IDS[index],it) } }
    if (style.getSource(PILE_SOURCE_ID)==null) style.addSource(GeoJsonSource(PILE_SOURCE_ID,FeatureCollection.fromFeatures(emptyArray<Feature>())))
    PILE_LAYER_IDS.forEachIndexed { index, layerId -> if(style.getLayer(layerId)==null) style.addLayerBelow(SymbolLayer(layerId,PILE_SOURCE_ID).withFilter(Expression.eq(Expression.get("pileType"),Expression.literal(index))).withProperties(PropertyFactory.iconImage(PILE_IMAGE_IDS[index]),PropertyFactory.iconAllowOverlap(true),PropertyFactory.iconIgnorePlacement(true),PropertyFactory.iconSize(0.72f)),PLAYER_LAYER_ID) }

    val poiDrawables = intArrayOf(R.drawable.poi_dog_park, R.drawable.poi_pet_shop, R.drawable.poi_veterinary, R.drawable.poi_grooming)
    poiDrawables.forEachIndexed { index, id ->
        BitmapFactory.decodeResource(context.resources, id)?.let { style.addImage(POI_IMAGE_IDS[index], it) }
    }
    if(style.getSource(NEARBY_PLAYER_SOURCE_ID)==null) style.addSource(GeoJsonSource(NEARBY_PLAYER_SOURCE_ID,FeatureCollection.fromFeatures(emptyArray<Feature>())))
    if(style.getLayer(NEARBY_PLAYER_LAYER_ID)==null) style.addLayerBelow(
        SymbolLayer(NEARBY_PLAYER_LAYER_ID,NEARBY_PLAYER_SOURCE_ID).withProperties(
            PropertyFactory.iconImage(PLAYER_IMAGE_ID),PropertyFactory.iconAllowOverlap(true),
            PropertyFactory.iconIgnorePlacement(true),PropertyFactory.iconSize(.55f)
        ),PLAYER_LAYER_ID
    )
    FLOCK_DOT_LAYER_IDS.forEachIndexed{i,layerId->if(style.getLayer(layerId)==null)style.addLayer(
        SymbolLayer(layerId,NEARBY_PLAYER_SOURCE_ID)
            .withFilter(Expression.gte(Expression.get("sharedFlocks"),Expression.literal(i+1)))
            .withProperties(PropertyFactory.iconImage(FLOCK_DOT_IMAGE_IDS[i]),PropertyFactory.iconAllowOverlap(true),PropertyFactory.iconIgnorePlacement(true),PropertyFactory.iconOffset(arrayOf(-12f+i*12f,30f)),PropertyFactory.iconSize(.7f))
    )}
    if(style.getSource(HOME_SOURCE_ID)==null)style.addSource(GeoJsonSource(HOME_SOURCE_ID,FeatureCollection.fromFeatures(emptyArray<Feature>())))
    if(style.getLayer(HOME_LAYER_ID)==null)style.addLayerBelow(SymbolLayer(HOME_LAYER_ID,HOME_SOURCE_ID).withProperties(PropertyFactory.iconImage(HOME_IMAGE_ID),PropertyFactory.iconAllowOverlap(true),PropertyFactory.iconIgnorePlacement(true),PropertyFactory.iconSize(.65f)),PLAYER_LAYER_ID)
    if (style.getSource(POI_SOURCE_ID) == null) {
        style.addSource(GeoJsonSource(POI_SOURCE_ID, FeatureCollection.fromFeatures(emptyArray<Feature>())))
    }
    POI_LAYER_IDS.forEachIndexed { index, layerId ->
        if (style.getLayer(layerId) == null) {
            style.addLayerBelow(
                SymbolLayer(layerId, POI_SOURCE_ID)
                    .withFilter(Expression.eq(Expression.get(POI_TYPE_PROPERTY), Expression.literal(POI_TYPES[index])))
                    .withProperties(
                        PropertyFactory.iconImage(POI_IMAGE_IDS[index]),
                        PropertyFactory.iconAllowOverlap(false),
                        PropertyFactory.iconIgnorePlacement(false),
                        PropertyFactory.iconSize(0.055f)
                    ),
                BONE_LAYER_IDS.first()
            )
        }
    }
}

private fun pileFeatureCollection(piles: List<DirtPile>): FeatureCollection = FeatureCollection.fromFeatures(piles.map { pile -> Feature.fromGeometry(Point.fromLngLat(pile.longitude,pile.latitude)).apply { addStringProperty(PILE_ID_PROPERTY,pile.id); addNumberProperty("pileType",pile.type.coerceIn(0,4)) } })

private fun nearbyPlayerFeatureCollection(players:List<NearbyPlayer>):FeatureCollection=FeatureCollection.fromFeatures(
    players.map { player->Feature.fromGeometry(Point.fromLngLat(player.longitude,player.latitude)).apply {
        addStringProperty("playerId",player.playerId);addNumberProperty("sharedFlocks",player.sharedFlockIds.size)
    }}
)

private fun poiFeatureCollection(pois: List<MapPoi>): FeatureCollection = FeatureCollection.fromFeatures(
    pois.map { poi ->
        Feature.fromGeometry(Point.fromLngLat(poi.longitude, poi.latitude)).apply {
            addStringProperty(POI_TYPE_PROPERTY, poi.poiType)
            addStringProperty("poiId", poi.poiId)
            poi.name?.let { addStringProperty("name", it) }
        }
    }
)

private fun poiTypeName(type:String)=when(type){"dog_park"->"Hundrastgård";"pet_shop"->"Djurbutik";"veterinary"->"Veterinär";"grooming"->"Hundtrim";else->"Hundtvätt"}

private fun playerFeatureCollection(player: GeoPoint?): FeatureCollection {
    if (player == null) return FeatureCollection.fromFeatures(emptyArray<Feature>())
    return FeatureCollection.fromFeatures(
        arrayOf(Feature.fromGeometry(Point.fromLngLat(player.longitude, player.latitude)))
    )
}

private fun boneFeatureCollection(bones: List<Bone>): FeatureCollection {
    val features = bones.map { bone ->
        Feature.fromGeometry(Point.fromLngLat(bone.longitude, bone.latitude)).apply {
            addStringProperty(BONE_ID_PROPERTY, bone.id)
            addNumberProperty(BONE_TYPE_PROPERTY, bone.type.coerceIn(0,11))
        }
    }
    return FeatureCollection.fromFeatures(features)
}

private fun pawBitmap(): Bitmap {
    val size = 112
    val b = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    val c = Canvas(b)
    val p = Paint(Paint.ANTI_ALIAS_FLAG)
    p.color = Color.argb(90, 0, 180, 255)
    c.drawCircle(56f, 59f, 50f, p)
    p.color = Color.WHITE
    c.drawCircle(56f, 60f, 34f, p)
    p.color = Color.rgb(0, 105, 230)
    c.drawOval(35f, 54f, 77f, 91f, p)
    c.drawCircle(29f, 44f, 12f, p)
    c.drawCircle(48f, 30f, 12f, p)
    c.drawCircle(69f, 30f, 12f, p)
    c.drawCircle(87f, 44f, 12f, p)
    return b
}

private fun homeBitmap():Bitmap{
    val b=Bitmap.createBitmap(112,112,Bitmap.Config.ARGB_8888);val c=Canvas(b);val p=Paint(Paint.ANTI_ALIAS_FLAG)
    p.color=Color.rgb(20,27,30);c.drawCircle(56f,56f,50f,p);p.color=Color.rgb(226,170,61);val roof=android.graphics.Path();roof.moveTo(18f,54f);roof.lineTo(56f,20f);roof.lineTo(94f,54f);roof.close();c.drawPath(roof,p);p.color=Color.rgb(255,229,176);c.drawRect(27f,50f,85f,90f,p);p.color=Color.rgb(22,141,138);c.drawRect(49f,66f,65f,90f,p);return b
}

private fun dotBitmap(color:Int):Bitmap{val b=Bitmap.createBitmap(24,24,Bitmap.Config.ARGB_8888);val c=Canvas(b);val p=Paint(Paint.ANTI_ALIAS_FLAG);p.color=Color.BLACK;c.drawCircle(12f,12f,11f,p);p.color=color;c.drawCircle(12f,12f,8f,p);return b}

private fun defaultMarkerBitmap(context: android.content.Context): Bitmap {
    val source = BitmapFactory.decodeResource(context.resources, R.drawable.marker_default_paw)
    val side = minOf(source.width, source.height)
    val cropSide = (side * 0.64f).toInt()
    val left = (source.width - cropSide) / 2
    val top = (source.height - cropSide) / 2
    val cropped = Bitmap.createBitmap(source, left, top, cropSide, cropSide)
    return Bitmap.createScaledBitmap(cropped, 112, 112, false)
}

private fun markerBitmap(context:android.content.Context,id:String):Bitmap {
    if(id=="marker_default_paw")return defaultMarkerBitmap(context)
    val size=112;val bitmap=Bitmap.createBitmap(size,size,Bitmap.Config.ARGB_8888);val canvas=Canvas(bitmap)
    val paint=Paint(Paint.ANTI_ALIAS_FLAG);val seed=id.hashCode();val palette=intArrayOf(
        Color.rgb(226,170,61),Color.rgb(22,141,138),Color.rgb(81,137,77),Color.rgb(46,125,170),Color.rgb(205,108,79),Color.rgb(163,113,190)
    );val accent=palette[Math.floorMod(seed,palette.size)]
    paint.color=Color.rgb(18,24,27);canvas.drawCircle(56f,56f,52f,paint);paint.style=Paint.Style.STROKE;paint.strokeWidth=6f;paint.color=if(id=="marker_frasse_mythic")Color.rgb(255,197,64) else accent;canvas.drawCircle(56f,56f,47f,paint);paint.style=Paint.Style.FILL
    when {
        id=="marker_frasse_mythic"||id.startsWith("marker_breed_")-> {
            paint.color=if(id=="marker_frasse_mythic")Color.rgb(225,173,108) else accent
            canvas.drawOval(27f,25f,85f,86f,paint);canvas.drawOval(17f,27f,37f,73f,paint);canvas.drawOval(75f,27f,95f,73f,paint)
            paint.color=Color.BLACK;canvas.drawCircle(46f,51f,4f,paint);canvas.drawCircle(66f,51f,4f,paint);canvas.drawOval(49f,62f,63f,72f,paint)
            if(id=="marker_frasse_mythic"){paint.color=Color.rgb(16,143,145);canvas.drawRect(31f,79f,81f,90f,paint)}
        }
        id.startsWith("marker_toy_")-> {paint.color=accent;canvas.drawCircle(56f,56f,29f,paint);paint.style=Paint.Style.STROKE;paint.color=Color.WHITE;paint.strokeWidth=5f;canvas.drawLine(31f,48f,81f,64f,paint);canvas.drawLine(43f,30f,61f,83f,paint);paint.style=Paint.Style.FILL}
        id.startsWith("marker_tag_")-> {paint.color=accent;val path=android.graphics.Path();path.moveTo(56f,22f);path.lineTo(88f,49f);path.lineTo(56f,91f);path.lineTo(24f,49f);path.close();canvas.drawPath(path,paint);paint.color=Color.WHITE;canvas.drawCircle(56f,43f,7f,paint)}
        id.startsWith("marker_gear_")-> {paint.style=Paint.Style.STROKE;paint.strokeWidth=11f;paint.color=accent;canvas.drawCircle(49f,57f,25f,paint);canvas.drawLine(68f,40f,89f,22f,paint);paint.style=Paint.Style.FILL}
        id.startsWith("marker_emblem_")-> {paint.color=accent;val path=android.graphics.Path();path.moveTo(56f,20f);path.lineTo(88f,33f);path.lineTo(81f,76f);path.lineTo(56f,94f);path.lineTo(31f,76f);path.lineTo(24f,33f);path.close();canvas.drawPath(path,paint);paint.color=Color.WHITE;canvas.drawCircle(56f,57f,12f,paint)}
        else->{paint.color=accent;canvas.drawOval(37f,51f,75f,87f,paint);listOf(32f to 43f,49f to 30f,67f to 30f,84f to 43f).forEach{canvas.drawCircle(it.first,it.second,10f,paint)}}
    }
    return bitmap
}

private fun boneBitmap(context: android.content.Context): Bitmap {
    val source = BitmapFactory.decodeResource(context.resources, R.drawable.bone_01)
    return Bitmap.createScaledBitmap(source, 104, 72, false)
}

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
    val tracker = remember { LocationTracker(context) }
    val scope = rememberCoroutineScope()

    var permissionGranted by remember {
        mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED)
    }
    var player by remember { mutableStateOf<GeoPoint?>(null) }
    var bones by remember { mutableStateOf(if (worldRepository==null) repository.loadBones() else emptyList()) }
    var piles by remember { mutableStateOf(if (worldRepository==null) repository.loadPiles() else emptyList()) }
    var mapPois by remember { mutableStateOf(emptyList<MapPoi>()) }
    var boneCount by remember(profile.playerId) { mutableIntStateOf(
        if (worldRepository==null) repository.boneCount()
        else profile.boneCount.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    ) }
    var loadingBones by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<String?>("Väntar på GPS…") }
    var followPlayer by remember { mutableStateOf(true) }
    var selectedBone by remember { mutableStateOf<Bone?>(null) }
    var menuOpen by remember { mutableStateOf(false) }
    var profileOpen by remember { mutableStateOf(false) }
    var collecting by remember { mutableStateOf(false) }
    var lastWorldLoadAt by remember { mutableLongStateOf(0L) }
    var lastWorldCenter by remember { mutableStateOf<GeoPoint?>(null) }
    var gpsHasBeenReady by remember { mutableStateOf(false) }
    var gpsWasInError by remember { mutableStateOf(false) }
    var startupTestBonePlaced by remember { mutableStateOf(false) }
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        permissionGranted = it
        if (!it) status = "GPS-behörighet behövs för att spela"
    }

    LaunchedEffect(Unit) {
        if (!permissionGranted) permissionLauncher.launch(Manifest.permission.ACCESS_FINE_LOCATION)
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
                        val presenceUpdated = runCatching { worldRepository.updatePresence(
                            point,location.accuracy,location.bearing,location.speed.takeIf { location.hasSpeed() }
                        ) }.isSuccess
                        // The server must know the same fresh position before
                        // the startup test bone is placed. Running these in
                        // separate coroutines could leave collection checking
                        // yesterday's stale presence for a few seconds.
                        if (presenceUpdated && location.accuracy <= 25 && !startupTestBonePlaced) {
                            startupTestBonePlaced = true
                            runCatching { worldRepository.placeStartupTestBone(point) }
                                .onFailure { startupTestBonePlaced = false }
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
                    distanceMeters(point.latitude, point.longitude, it.latitude, it.longitude) <= 3_500.0
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
    LaunchedEffect(nearBone) { selectedBone = nearBone }

    MaterialTheme(colorScheme = darkColorScheme()) {
        Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color(0xFF08131B))) {
            GameMap(
                player = player,
                bones = bones,
                piles = piles,
                pois = mapPois,
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
                    status = "BEN  •  VÄRDE ${boneValue(bone.type)}  •  ${distance?.let { "$it M" } ?: "OKÄNT AVSTÅND"}"
                },
                onPlayerTapped = { profileOpen = true },
                onPileTapped = { pile ->
                    val p = player
                    val d = if (p == null) 9999.0 else distanceMeters(p.latitude,p.longitude,pile.latitude,pile.longitude)
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
                            .align(Alignment.BottomCenter)
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

        if (menuOpen) {
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
            Text(label,Modifier.padding(start=12.dp),color=androidx.compose.ui.graphics.Color(0xFFFFD78D),fontWeight=FontWeight.Black,fontSize=18.sp)
            Spacer(Modifier.weight(1f))
            Text(detail,Modifier.padding(end=18.dp),color=androidx.compose.ui.graphics.Color(0xFFFFD78D),fontWeight=FontWeight.Black,fontSize=15.sp)
        }
    }
}

@Composable
private fun GameMap(
    player: GeoPoint?, bones: List<Bone>, piles: List<DirtPile>, pois: List<MapPoi>, followPlayer: Boolean,
    onManualMove: () -> Unit, onBoundsChanged: (MapBounds) -> Unit, onBoneTapped: (Bone) -> Unit,
    onPlayerTapped: () -> Unit, onPileTapped: (DirtPile) -> Unit, modifier: Modifier
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
                    val feature = libreMap.queryRenderedFeatures(
                        hitArea,
                        *(BONE_LAYER_IDS + PILE_LAYER_IDS + arrayOf(PLAYER_LAYER_ID))
                    ).firstOrNull()
                    val boneId = feature
                        ?.properties()
                        ?.get(BONE_ID_PROPERTY)
                        ?.asString
                    if (boneId != null) {
                        latestBones.firstOrNull { it.id == boneId }?.let(latestBoneTap); true
                    } else {
                        val pileId = feature?.properties()?.get(PILE_ID_PROPERTY)?.asString
                        if (pileId != null) { latestPiles.firstOrNull { it.id == pileId }?.let(latestPileTap); true }
                        else if (feature != null) { latestPlayerTap(); true } else false
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

    LaunchedEffect(map, styleReady, player, followPlayer) {
        val m = map ?: return@LaunchedEffect
        if (!styleReady) return@LaunchedEffect
        val style = m.style ?: return@LaunchedEffect
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

private fun poiFeatureCollection(pois: List<MapPoi>): FeatureCollection = FeatureCollection.fromFeatures(
    pois.map { poi ->
        Feature.fromGeometry(Point.fromLngLat(poi.longitude, poi.latitude)).apply {
            addStringProperty(POI_TYPE_PROPERTY, poi.poiType)
            addStringProperty("poiId", poi.poiId)
            poi.name?.let { addStringProperty("name", it) }
        }
    }
)

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

private fun defaultMarkerBitmap(context: android.content.Context): Bitmap {
    val source = BitmapFactory.decodeResource(context.resources, R.drawable.marker_default_paw)
    val side = minOf(source.width, source.height)
    val cropSide = (side * 0.64f).toInt()
    val left = (source.width - cropSide) / 2
    val top = (source.height - cropSide) / 2
    val cropped = Bitmap.createBitmap(source, left, top, cropSide, cropSide)
    return Bitmap.createScaledBitmap(cropped, 112, 112, false)
}

private fun boneBitmap(context: android.content.Context): Bitmap {
    val source = BitmapFactory.decodeResource(context.resources, R.drawable.bone_01)
    return Bitmap.createScaledBitmap(source, 104, 72, false)
}

package se.frasse.bonequest.walking

import android.Manifest
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import android.media.AudioManager
import android.media.ToneGenerator
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.*
import kotlinx.coroutines.*
import se.frasse.bonequest.MainActivity
import se.frasse.bonequest.R
import se.frasse.bonequest.SupabaseProvider
import se.frasse.bonequest.GeoPoint
import se.frasse.bonequest.WorldRepository
import kotlinx.coroutines.flow.first
import java.text.NumberFormat
import java.util.Locale
import kotlin.math.roundToInt

class WalkingLocationService : Service() {
    private val serviceScope=CoroutineScope(SupervisorJob()+Dispatchers.IO)
    private lateinit var fused:FusedLocationProviderClient
    private lateinit var queue:DistanceQueue
    private val filter=DistanceFilter()
    private var pendingMeters=0.0
    private var batchStartedAt=0L
    private var sessionMeters=0.0
    private var nearbyBones=0
    private var insideBoneZone=false

    private val callback=object:LocationCallback() {
        override fun onLocationResult(result:LocationResult) {
            for (location in result.locations) {
                val sample=LocationSample(
                    location.latitude,location.longitude,location.accuracy,
                    location.elapsedRealtimeNanos/1_000_000,
                    location.speed.takeIf { location.hasSpeed() }
                )
                filter.add(sample)?.let { segment ->
                    if (batchStartedAt==0L) batchStartedAt=System.currentTimeMillis()
                    pendingMeters+=segment.meters; sessionMeters+=segment.meters
                    updateNotification()
                    if (System.currentTimeMillis()-batchStartedAt>=60_000) flushBatch()
                }
                serviceScope.launch {
                    SupabaseProvider.clientOrNull?.let { client ->
                        runCatching { DistanceSyncRepository(client).updatePresence(sample,location.bearing,true) }
                        runCatching { WorldRepository(client).loadNearby(GeoPoint(sample.latitude,sample.longitude),40.0) }
                            .onSuccess { world ->
                                nearbyBones=world.bones.size
                                if(nearbyBones>0&&!insideBoneZone){insideBoneZone=true;alertForBone()}
                                if(nearbyBones==0)insideBoneZone=false
                                updateNotification()
                            }
                    }
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate(); createChannel()
        fused=LocationServices.getFusedLocationProviderClient(this); queue=DistanceQueue(this)
    }

    override fun onStartCommand(intent:Intent?,flags:Int,startId:Int):Int {
        if (intent?.action==ACTION_STOP) { stopWalking(); return START_NOT_STICKY }
        startForeground(NOTIFICATION_ID,buildNotification())
        if (ContextCompat.checkSelfPermission(this,Manifest.permission.ACCESS_FINE_LOCATION)!=PackageManager.PERMISSION_GRANTED) {
            stopWalking(); return START_NOT_STICKY
        }
        val request=LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY,10_000)
            .setMinUpdateIntervalMillis(5_000).setMaxUpdateDelayMillis(15_000).build()
        fused.requestLocationUpdates(request,callback,mainLooper)
        serviceScope.launch { syncQueuedBatches() }
        return START_STICKY
    }

    override fun onDestroy() {
        fused.removeLocationUpdates(callback); flushBatch(); serviceScope.cancel(); super.onDestroy()
    }
    override fun onBind(intent:Intent?):IBinder?=null

    private fun flushBatch() {
        if (pendingMeters<1 || batchStartedAt==0L) return
        val batch=DistanceBatch(
            meters=pendingMeters.roundToInt(),startedAtEpochMillis=batchStartedAt,
            endedAtEpochMillis=System.currentTimeMillis()
        )
        queue.enqueue(batch); pendingMeters=0.0; batchStartedAt=0L
        serviceScope.launch { syncQueuedBatches() }
    }

    private suspend fun syncQueuedBatches() {
        val client=SupabaseProvider.clientOrNull ?: return
        val repository=DistanceSyncRepository(client)
        for (batch in queue.load()) {
            if (runCatching { repository.sync(batch) }.isSuccess) queue.remove(batch.id) else break
        }
    }

    private fun stopWalking() {
        flushBatch(); fused.removeLocationUpdates(callback); stopForeground(STOP_FOREGROUND_REMOVE); stopSelf()
    }

    private fun createChannel() {
        val manager=getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(
            CHANNEL_ID,getString(R.string.walking_channel_name),NotificationManager.IMPORTANCE_LOW
        ).apply { description=getString(R.string.walking_notification_title); setShowBadge(false) })
    }

    private fun buildNotification():Notification {
        val open=PendingIntent.getActivity(this,0,Intent(this,MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop=PendingIntent.getService(this,1,Intent(this,WalkingLocationService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val km=NumberFormat.getNumberInstance(Locale.forLanguageTag("sv-SE")).apply {
            minimumFractionDigits=2; maximumFractionDigits=2
        }.format(sessionMeters/1000.0)
        return NotificationCompat.Builder(this,CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle(getString(R.string.walking_notification_title))
            .setContentText(getString(R.string.walking_notification_status,km,nearbyBones))
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
            .addAction(0,getString(R.string.walking_notification_stop),stop).build()
    }

    private fun updateNotification() {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID,buildNotification())
    }

    private suspend fun alertForBone() {
        val preferences=WalkingPreferences(this)
        if(preferences.vibrationEnabled.first()) {
            getSystemService(Vibrator::class.java)?.vibrate(VibrationEffect.createOneShot(450,VibrationEffect.DEFAULT_AMPLITUDE))
        }
        if(preferences.barkEnabled.first()) {
            withContext(Dispatchers.Main) {
                ToneGenerator(AudioManager.STREAM_NOTIFICATION,80).also { tone ->
                    tone.startTone(ToneGenerator.TONE_PROP_BEEP2,180)
                    serviceScope.launch { delay(230);withContext(Dispatchers.Main){tone.startTone(ToneGenerator.TONE_PROP_BEEP2,220)};delay(260);tone.release() }
                }
            }
        }
    }

    companion object {
        private const val CHANNEL_ID="fbq_walking"; private const val NOTIFICATION_ID=400
        private const val ACTION_STOP="se.frasse.bonequest.STOP_WALKING"
    }
}

object WalkingServiceController {
    fun start(context:Context) {
        ContextCompat.startForegroundService(context,Intent(context,WalkingLocationService::class.java))
    }
    fun stop(context:Context) {
        context.startService(Intent(context,WalkingLocationService::class.java).setAction("se.frasse.bonequest.STOP_WALKING"))
    }
}

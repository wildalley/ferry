package com.wildalley.ferry

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import io.nekohasekai.libbox.CommandClient
import io.nekohasekai.libbox.CommandClientHandler
import io.nekohasekai.libbox.CommandClientOptions
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.ConnectionEvents
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LogIterator
import io.nekohasekai.libbox.OutboundGroupIterator
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.StatusMessage
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.SystemProxyStatus
import java.io.File
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/**
 * Runs sing-box inside a [VpnService].
 *
 * libbox owns the proxy engine; this service owns the Android VPN lifecycle.
 * [CommandServer] drives the engine, [CommandClient] subscribes to its status
 * and log streams, and both are forwarded to Flutter through [BoxEvents].
 */
class SingBoxVpnService : VpnService() {

    private var commandServer: CommandServer? = null
    private var commandClient: CommandClient? = null
    private var tunDescriptor: ParcelFileDescriptor? = null
    private val platform by lazy { BoxPlatform(this) }

    /** Drops callbacks that were queued by libbox after a failed start/stop. */
    @Volatile
    private var acceptingLogs = false

    private val generation = AtomicLong()
    // Only short state transitions hold this lock; no engine I/O is inside it.
    private val stateLock = Any()

    private fun newGeneration(): Long = synchronized(stateLock) {
        acceptingLogs = false
        generation.incrementAndGet()
    }

    private fun transition(token: Long, stage: BoxEvents.Stage, detail: String? = null) {
        synchronized(stateLock) {
            if (current(token)) BoxEvents.setStage(stage, detail)
        }
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    private val tunLock = Any()
    @Volatile private var destroyed = false
    @Volatile private var serverLease: Any? = null

    private fun current(token: Long) = !destroyed && generation.get() == token

    // All Go calls share one process-wide executor. A replacement Service
    // cannot start an engine while the destroyed instance is still closing.
    private fun enqueueCommand(done: (Throwable?) -> Unit, block: () -> Unit) {
        val token = generation.get()
        engineExecutor.execute {
            val error = runCatching {
                check(current(token)) { "Tunnel operation cancelled" }
                block()
                check(current(token)) { "Tunnel operation cancelled" }
            }.exceptionOrNull()
            mainHandler.post { done(error) }
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            requestStop()
            return START_NOT_STICKY
        }

        val config = intent?.getStringExtra(EXTRA_CONFIG)
        if (config.isNullOrEmpty()) {
            // Restarted by the system without a config: nothing to resume.
            stopSelf()
            return START_NOT_STICKY
        }

        startForegroundNotification(getString(R.string.notification_connecting))
        // Engine startup does blocking IO (rule-set downloads, DNS), so keep it
        // off the main thread or the service will ANR.
        val token = newGeneration()
        acceptingLogs = false
        engineExecutor.execute { runCatching { startTunnel(config, token) } }
        return START_STICKY
    }

    override fun onRevoke() {
        // The user revoked VPN permission, or another VPN took over.
        BoxEvents.setStage(BoxEvents.Stage.ERROR, "VPN permission was revoked")
        requestStop()
        super.onRevoke()
    }

    override fun onDestroy() {
        synchronized(stateLock) {
            destroyed = true
            generation.incrementAndGet()
            acceptingLogs = false
            if (instance === this && BoxEvents.stage != BoxEvents.Stage.ERROR) {
                BoxEvents.beginSession()
                BoxEvents.setStage(BoxEvents.Stage.DISCONNECTED)
            }
        }
        engineExecutor.execute { closeEngine() }
        if (instance === this) instance = null
        super.onDestroy()
    }

    // ------------------------------------------------------------------ engine

    private fun setupLibbox() {
        if (libboxReady) return
        val working = File(filesDir, "work").apply { mkdirs() }
        val temp = File(cacheDir, "temp").apply { mkdirs() }
        run {
            Libbox.setup(
                SetupOptions().apply {
                    basePath = filesDir.absolutePath
                    workingPath = working.absolutePath
                    tempPath = temp.absolutePath
                    // Works around a Go runtime stack issue on Android.
                    fixAndroidStack = true
                    logMaxLines = 300
                }
            )
            Libbox.configureFerryMemory()
            libboxReady = true
        }
    }

    private fun startTunnel(config: String, token: Long) {
        if (!current(token)) return
        try {
            setupLibbox()
            synchronized(stateLock) {
                if (!current(token)) return
                BoxEvents.beginSession()
                BoxEvents.setStage(BoxEvents.Stage.STARTING)
            }
            acceptingLogs = false
            // Replace the subscription on reload so old callbacks retain the
            // old generation and can never be relabelled as current traffic.
            runCatching { commandClient?.disconnect() }
            commandClient = null
            if (!current(token)) return
            acceptingLogs = true
            var server = commandServer
            if (server == null) {
                val lease = Any()
                serverLease = lease
                server = Libbox.newCommandServer(ServerHandler(lease), platform)
                commandServer = server // own before the first throwing call
                server.start()
            }
            if (!current(token)) { closeEngine(); return }
            server.startOrReloadService(config, OverrideOptions())
            if (!current(token)) { closeEngine(); return }
            connectCommandClient(token)
            if (!current(token)) { closeEngine(); return }
            transition(token, BoxEvents.Stage.CONNECTED)
            mainHandler.post {
                if (current(token)) updateNotification(getString(R.string.notification_connected))
            }
        } catch (error: Throwable) {
            fail(error, token)
            closeEngine()
            finishStop(token)
            throw error
        }
    }

    private fun requestStop() {
        val token = synchronized(stateLock) {
            val next = newGeneration()
            BoxEvents.beginSession()
            if (BoxEvents.stage != BoxEvents.Stage.ERROR) {
                BoxEvents.setStage(BoxEvents.Stage.STOPPING)
            } else {
                BoxEvents.setStage(BoxEvents.Stage.ERROR, BoxEvents.message)
            }
            next
        }
        engineExecutor.execute {
            if (!current(token)) return@execute
            closeEngine()
            if (current(token) && BoxEvents.stage != BoxEvents.Stage.ERROR) {
                transition(token, BoxEvents.Stage.DISCONNECTED)
            }
            finishStop(token)
        }
    }

    private fun finishStop(token: Long) {
        mainHandler.post {
            // A newer start may already be queued while Go was shutting down.
            if (current(token)) {
                stopForegroundCompat()
                stopSelf()
            }
        }
    }

    /** Only called on the engine executor, including partial-start failures. */
    private fun closeEngine() {
        acceptingLogs = false
        serverLease = null
        BoxEvents.resetLogThrottle()
        val client = commandClient
        commandClient = null
        runCatching { client?.disconnect() }
        val server = commandServer
        commandServer = null
        runCatching { server?.closeService() }
        runCatching { server?.close() }
        synchronized(tunLock) {
            runCatching { tunDescriptor?.close() }
            tunDescriptor = null
        }
    }

    fun reload(config: String, done: (Throwable?) -> Unit) {
        val token = newGeneration()
        acceptingLogs = false
        engineExecutor.execute {
            val error = runCatching {
                check(current(token)) { "Tunnel operation cancelled" }
                check(commandServer != null) { "Tunnel is not connected" }
                startTunnel(config, token)
                check(current(token)) { "Tunnel operation cancelled" }
            }.exceptionOrNull()
            mainHandler.post { done(error) }
        }
    }

    fun selectOutbound(group: String, tag: String, done: (Throwable?) -> Unit) =
        enqueueCommand(done) {
            val client = commandClient ?: error("Tunnel is not connected")
            client.selectOutbound(group, tag)
        }

    fun urlTest(group: String, done: (Throwable?) -> Unit) = enqueueCommand(done) {
        val client = commandClient ?: error("Tunnel is not connected")
        client.urlTest(group)
    }

    fun clearLogs(done: (Throwable?) -> Unit) = enqueueCommand(done) {
        commandClient?.clearLogs()
    }

    private fun connectCommandClient(token: Long) {
        val options = CommandClientOptions().apply {
            statusInterval = STATUS_INTERVAL_NANOS
            addCommand(Libbox.CommandStatus)
            addCommand(Libbox.CommandLog)
            addCommand(Libbox.CommandGroup)
        }
        val client = Libbox.newCommandClient(ClientHandler(token), options)
        commandClient = client // connect can throw after allocating resources
        client.connect()
    }

    private fun fail(error: Throwable, token: Long) {
        // Stop forwarding immediately, even when a reload fails and the
        // service is still alive long enough for libbox to flush its queue.
        acceptingLogs = false
        Log.e(TAG, "sing-box failure (${error.javaClass.simpleName})")
        transition(token, BoxEvents.Stage.ERROR, "Proxy engine operation failed")
    }

    // --------------------------------------------------------------- tun state

    /**
     * [Builder] is a non-static inner class, so only this service can create
     * one. [BoxPlatform] goes through here.
     */
    fun newBuilder(): Builder = Builder()

    /** Called by [BoxPlatform] after `establish()` so the fd stays open. */
    fun retainTunDescriptor(descriptor: ParcelFileDescriptor) {
        synchronized(tunLock) {
            if (destroyed || !acceptingLogs) {
                descriptor.close()
                error("Tunnel start was cancelled")
            }
            runCatching { tunDescriptor?.close() }
            tunDescriptor = descriptor
        }
    }

    // ------------------------------------------------------------- notification

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                getString(R.string.notification_channel_name),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                setShowBadge(false)
                description = getString(R.string.notification_channel_description)
            }
        )
    }

    private fun buildNotification(text: String): Notification {
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, SingBoxVpnService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle(getString(R.string.app_name))
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_tunnel)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(
                Notification.Action.Builder(
                    null,
                    getString(R.string.notification_action_stop),
                    stopIntent,
                ).build()
            )
            .build()
    }

    private fun startForegroundNotification(text: String) {
        val notification = buildNotification(text)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateNotification(text: String) {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        runCatching { manager.notify(NOTIFICATION_ID, buildNotification(text)) }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    // ------------------------------------------------------------- libbox hooks

    /** Commands libbox sends back to the platform. */
    private inner class ServerHandler(private val lease: Any) : CommandServerHandler {
        override fun serviceStop() {
            if (serverLease === lease && acceptingLogs) requestStop()
        }

        override fun serviceReload() {
            // Reload is driven from Flutter, so there is nothing to do here.
        }

        override fun getSystemProxyStatus(): SystemProxyStatus =
            SystemProxyStatus().apply {
                // Android routes everything through the tun; there is no
                // separate system-proxy toggle to report.
                available = false
                enabled = false
            }

        override fun setSystemProxyEnabled(enabled: Boolean) = Unit

        override fun triggerNativeCrash() {
            throw UnsupportedOperationException("Native crash injection is disabled")
        }

        override fun connectSSHAgent(): Int =
            throw UnsupportedOperationException("SSH agent forwarding is unavailable")

        override fun writeDebugMessage(message: String) {
            Log.d(TAG, message)
        }
    }

    /** Status and log streams from the running engine. */
    private inner class ClientHandler(private val token: Long) : CommandClientHandler {
        private val eventSession = BoxEvents.session
        private fun active() = acceptingLogs && current(token)
        override fun connected() = Unit

        override fun disconnected(message: String) {
            if (active() && message.isNotEmpty()) {
                BoxEvents.emitLog("disconnected: $message", eventSession)
            }
        }

        override fun writeStatus(message: StatusMessage) {
            if (!active()) return
            BoxEvents.emitTraffic(
                uplink = message.uplink,
                downlink = message.downlink,
                uplinkTotal = message.uplinkTotal,
                downlinkTotal = message.downlinkTotal,
                connectionsIn = message.connectionsIn,
                connectionsOut = message.connectionsOut,
                memory = message.memory,
                eventSession = eventSession,
            )
        }

        override fun writeLogs(messageList: LogIterator) {
            while (active() && messageList.hasNext()) {
                BoxEvents.emitLog(messageList.next().message, eventSession)
            }
        }

        override fun clearLogs() { if (active()) BoxEvents.resetLogThrottle() }

        override fun setDefaultLogLevel(level: Int) = Unit

        override fun initializeClashMode(modeList: StringIterator, currentMode: String) = Unit

        override fun updateClashMode(newMode: String) = Unit

        /**
         * Group state, including each member's last URL-test delay.
         *
         * The iterators are only valid for the duration of this call — they are
         * views onto memory libbox owns — so everything is copied into plain maps
         * before it leaves. Flattened here rather than in Dart because the
         * channel cannot carry the iterator itself.
         */
        override fun writeGroups(message: OutboundGroupIterator) {
            if (!active()) return
            val groups = mutableListOf<Map<String, Any?>>()
            while (message.hasNext()) {
                val group = message.next()
                val items = mutableListOf<Map<String, Any?>>()
                val iterator = group.items
                while (iterator.hasNext()) {
                    val item = iterator.next()
                    items.add(
                        mapOf(
                            "tag" to item.tag,
                            "type" to item.type,
                            // 0 is libbox's "no result": either never tested or the
                            // last test failed. Dart decides what that means.
                            //
                            // The getter rather than property syntax: Kotlin's
                            // synthesis of `getURLTestDelay` over a leading
                            // acronym is not something to bet a build on.
                            "delay" to item.getURLTestDelay(),
                        )
                    )
                }
                groups.add(
                    mapOf(
                        "tag" to group.tag,
                        "type" to group.type,
                        "selected" to group.selected,
                        "items" to items,
                    )
                )
            }
            if (active() && groups.isNotEmpty()) BoxEvents.emitGroups(groups, eventSession)
        }

        override fun writeConnectionEvents(events: ConnectionEvents) = Unit

        // This client subscribes to groups, not the optional flat outbound list.
        override fun writeOutbounds(message: io.nekohasekai.libbox.OutboundGroupItemIterator) = Unit
    }

    companion object {
        private val engineExecutor = Executors.newSingleThreadExecutor { task ->
            Thread(task, "ferry-engine").apply { isDaemon = true }
        }
        const val ACTION_STOP = "com.wildalley.ferry.STOP"
        const val EXTRA_CONFIG = "config"

        private const val TAG = "SingBoxVpn"
        private const val CHANNEL_ID = "singbox-tunnel"
        private const val NOTIFICATION_ID = 1

        /** libbox reports status on this interval, in nanoseconds. */
        private const val STATUS_INTERVAL_NANOS = 1_000_000_000L

        /** `Libbox.setup` is process-global and must run only once. */
        @Volatile
        private var libboxReady = false

        /** Lets the Flutter plugin talk to a service that is already running. */
        @Volatile
        var instance: SingBoxVpnService? = null
            private set
    }
}

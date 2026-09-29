package dev.fourbit.kamidrop

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.Inet4Address

/**
 * Нативна частина KamiDrop:
 *  - пошук принтерів через системний NsdManager (DNS-SD). Android не дає звичайним
 *    застосункам надсилати mDNS-запити самотужки, а NsdManager робить це від імені системи;
 *  - multicast lock (запасний варіант для Dart-реалізації mDNS);
 *  - прийом файлів через «Поділитися → KamiDrop» і «Відкрити за допомогою».
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var pendingSharedPath: String? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private var nsd: NsdManager? = null
    private val discoveryListeners = mutableListOf<NsdManager.DiscoveryListener>()
    private val resolveQueue = ArrayDeque<NsdServiceInfo>()
    private var resolvingToken: Any? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingSharedPath = extractSharedFile(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kamidrop/platform").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "startPrinterDiscovery" -> {
                        startDiscovery()
                        result.success(null)
                    }
                    "stopPrinterDiscovery" -> {
                        stopDiscovery()
                        result.success(null)
                    }
                    "acquireMulticastLock" -> {
                        acquireMulticastLock()
                        result.success(null)
                    }
                    "releaseMulticastLock" -> {
                        releaseMulticastLock()
                        result.success(null)
                    }
                    "takeSharedFile" -> {
                        result.success(pendingSharedPath)
                        pendingSharedPath = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val path = extractSharedFile(intent) ?: return
        channel?.invokeMethod("sharedFile", path)
    }

    override fun onDestroy() {
        stopDiscovery()
        releaseMulticastLock()
        super.onDestroy()
    }

    // ------------------------------------------------------------------ пошук принтерів (NSD)

    /** Перезапускає пошук: кожен перезапуск змушує систему заново опитати мережу. */
    private fun startDiscovery() {
        stopDiscovery()
        val manager = getSystemService(Context.NSD_SERVICE) as NsdManager
        nsd = manager
        for (type in listOf("_ipp._tcp", "_ipps._tcp")) {
            val listener = object : NsdManager.DiscoveryListener {
                override fun onDiscoveryStarted(serviceType: String) {}
                override fun onDiscoveryStopped(serviceType: String) {}
                override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {}
                override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
                override fun onServiceLost(serviceInfo: NsdServiceInfo) {}
                override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                    mainHandler.post { enqueueResolve(serviceInfo) }
                }
            }
            try {
                manager.discoverServices(type, NsdManager.PROTOCOL_DNS_SD, listener)
                discoveryListeners.add(listener)
            } catch (_: Exception) {
            }
        }
    }

    private fun stopDiscovery() {
        val manager = nsd ?: return
        for (l in discoveryListeners) {
            try {
                manager.stopServiceDiscovery(l)
            } catch (_: Exception) {
            }
        }
        discoveryListeners.clear()
        resolveQueue.clear()
        resolvingToken = null
    }

    private fun enqueueResolve(info: NsdServiceInfo) {
        if (resolveQueue.any { it.serviceName == info.serviceName && it.serviceType == info.serviceType }) return
        resolveQueue.addLast(info)
        resolveNext()
    }

    /** Розв'язуємо сервіси по одному: старі версії NsdManager не вміють кілька одночасно. */
    private fun resolveNext() {
        if (resolvingToken != null) return
        val info = resolveQueue.removeFirstOrNull() ?: return
        val manager = nsd ?: return
        val token = Any()
        resolvingToken = token

        if (Build.VERSION.SDK_INT >= 34) {
            val callback = object : NsdManager.ServiceInfoCallback {
                override fun onServiceInfoCallbackRegistrationFailed(errorCode: Int) = resolveDone(token)
                override fun onServiceUpdated(serviceInfo: NsdServiceInfo) {
                    report(serviceInfo)
                    try {
                        manager.unregisterServiceInfoCallback(this)
                    } catch (_: Exception) {
                        resolveDone(token)
                    }
                }
                override fun onServiceLost() {}
                override fun onServiceInfoCallbackUnregistered() = resolveDone(token)
            }
            try {
                manager.registerServiceInfoCallback(info, mainExecutor, callback)
                // Якщо принтер так і не відповів — не блокуємо чергу.
                mainHandler.postDelayed({
                    if (resolvingToken === token) {
                        try {
                            manager.unregisterServiceInfoCallback(callback)
                        } catch (_: Exception) {
                        }
                        resolveDone(token)
                    }
                }, 5000)
            } catch (_: Exception) {
                resolveDone(token)
            }
        } else {
            @Suppress("DEPRECATION")
            manager.resolveService(info, object : NsdManager.ResolveListener {
                override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                    mainHandler.post { resolveDone(token) }
                }

                override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                    mainHandler.post {
                        report(serviceInfo)
                        resolveDone(token)
                    }
                }
            })
        }
    }

    private fun resolveDone(token: Any) {
        if (resolvingToken !== token) return
        resolvingToken = null
        resolveNext()
    }

    private fun report(info: NsdServiceInfo) {
        val host: String? = if (Build.VERSION.SDK_INT >= 34) {
            val addrs = info.hostAddresses
            (addrs.firstOrNull { it is Inet4Address } ?: addrs.firstOrNull())?.hostAddress
        } else {
            @Suppress("DEPRECATION")
            info.host?.hostAddress
        }
        if (host == null) return
        val txt = HashMap<String, String>()
        for ((k, v) in info.attributes) {
            txt[k.lowercase()] = if (v != null) String(v, Charsets.UTF_8) else ""
        }
        channel?.invokeMethod(
            "printerFound",
            mapOf(
                "name" to info.serviceName,
                "host" to host,
                "port" to info.port,
                "tls" to (info.serviceType?.contains("_ipps") == true),
                "txt" to txt,
            ),
        )
    }

    // ------------------------------------------------------------------ multicast lock

    private fun acquireMulticastLock() {
        if (multicastLock?.isHeld == true) return
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifi.createMulticastLock("kamidrop-mdns").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseMulticastLock() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
    }

    // ------------------------------------------------------------------ файли з «Поділитися»

    private fun extractSharedFile(intent: Intent?): String? {
        if (intent == null) return null
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_SEND ->
                if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
                }
            Intent.ACTION_VIEW -> intent.data
            else -> null
        }
        if (uri == null) return null
        return try {
            copyToCache(uri)
        } catch (e: Exception) {
            null
        }
    }

    private fun copyToCache(uri: Uri): String {
        var name: String? = null
        if (uri.scheme == "content") {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) name = c.getString(0)
            }
        }
        if (name.isNullOrBlank()) name = uri.lastPathSegment ?: "shared"
        var fileName = name!!.substringAfterLast('/')
        if (!fileName.contains('.')) {
            val mime = contentResolver.getType(uri) ?: ""
            val ext = when {
                mime == "application/pdf" -> "pdf"
                mime == "image/png" -> "png"
                mime == "image/webp" -> "webp"
                mime.startsWith("image/") -> "jpg"
                else -> "bin"
            }
            fileName = "$fileName.$ext"
        }
        // Тримаємо в кеші лише останній отриманий файл.
        val dir = File(cacheDir, "shared").apply {
            mkdirs()
            listFiles()?.forEach { it.delete() }
        }
        val out = File(dir, fileName)
        contentResolver.openInputStream(uri)!!.use { input ->
            out.outputStream().use { output -> input.copyTo(output) }
        }
        return out.absolutePath
    }
}

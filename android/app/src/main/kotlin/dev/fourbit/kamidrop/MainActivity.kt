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
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.Inet4Address
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Нативна частина KamiDrop:
 *  - пошук принтерів через системний NsdManager (DNS-SD). Android не дає звичайним
 *    застосункам надсилати mDNS-запити самотужки, а NsdManager робить це від імені системи;
 *  - multicast lock (запасний варіант для Dart-реалізації mDNS);
 *  - прийом файлів через «Поділитися → KamiDrop» і «Відкрити за допомогою»;
 *  - вибір фото з галереї (системний Photo Picker).
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var pendingSharedPath: String? = null
    private var pendingPick: MethodChannel.Result? = null

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
                    "pickImage" -> pickImage(result)
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

    @Deprecated("startActivityForResult — найпростіше для FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PICK_IMAGE) return
        val result = pendingPick ?: return
        pendingPick = null
        val uri = if (resultCode == RESULT_OK) data?.data else null
        if (uri == null) {
            result.success(null)
            return
        }
        try {
            result.success(copyToCache(uri, "picked"))
        } catch (e: Exception) {
            result.error("pick", e.message, null)
        }
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

    // ------------------------------------------------------------------ фото з галереї

    /** Android 13+ — системний Photo Picker (без дозволів); раніше — звичайний вибір зображення. */
    private fun pickImage(result: MethodChannel.Result) {
        pendingPick?.success(null) // попередній вибір так і не завершився
        pendingPick = result
        val intent = if (Build.VERSION.SDK_INT >= 33) {
            Intent(MediaStore.ACTION_PICK_IMAGES).setType("image/*")
        } else {
            Intent(Intent.ACTION_GET_CONTENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE)
        }
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQUEST_PICK_IMAGE)
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

    /** Копіює вміст [uri] у cache/[dirName], тримаючи там лише останній файл. */
    private fun copyToCache(uri: Uri, dirName: String = "shared"): String {
        var name: String? = null
        var dateTaken: Long? = null
        if (uri.scheme == "content") {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) name = c.getString(0)
            }
            // Photo Picker ховає справжню назву («1000029278.jpg»), але віддає дату зйомки.
            try {
                contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DATE_TAKEN), null, null, null)?.use { c ->
                    if (c.moveToFirst() && !c.isNull(0)) dateTaken = c.getLong(0)
                }
            } catch (_: Exception) {}
        }
        if (name.isNullOrBlank()) name = uri.lastPathSegment ?: "shared"
        var fileName = name!!.substringAfterLast('/')
        val ext = fileName.substringAfterLast('.', "").ifEmpty {
            val mime = contentResolver.getType(uri) ?: ""
            when {
                mime == "application/pdf" -> "pdf"
                mime == "image/png" -> "png"
                mime == "image/webp" -> "webp"
                mime.startsWith("image/") -> "jpg"
                else -> "bin"
            }
        }
        val base = fileName.substringBeforeLast('.')
        val taken = dateTaken
        fileName = when {
            base.all { it.isDigit() } && taken != null && taken > 0 ->
                "Фото ${SimpleDateFormat("dd.MM.yyyy HH:mm", Locale.ROOT).format(Date(taken))}.$ext"
            base.all { it.isDigit() } -> "Фото.$ext"
            else -> "$base.$ext"
        }
        val dir = File(cacheDir, dirName).apply {
            mkdirs()
            listFiles()?.forEach { it.delete() }
        }
        val out = File(dir, fileName)
        contentResolver.openInputStream(uri)!!.use { input ->
            out.outputStream().use { output -> input.copyTo(output) }
        }
        return out.absolutePath
    }

    companion object {
        private const val REQUEST_PICK_IMAGE = 4201
    }
}

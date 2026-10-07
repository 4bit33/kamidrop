package dev.fourbit.kamidrop

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.net.Inet4Address

/**
 * Пошук принтерів і сканерів через системний NsdManager (DNS-SD). Android не дає звичайним
 * застосункам надсилати mDNS-запити самотужки, а NsdManager робить це від імені системи.
 * Спільний для вікна застосунку й служби друку: знахідки віддає в [onFound]
 * (name, host, port, tls, scanner, txt). Плюс multicast lock — запас для Dart-mDNS.
 */
class NsdDiscovery(private val context: Context, private val onFound: (Map<String, Any>) -> Unit) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var nsd: NsdManager? = null
    private val discoveryListeners = mutableListOf<NsdManager.DiscoveryListener>()
    private val resolveQueue = ArrayDeque<NsdServiceInfo>()
    private var resolvingToken: Any? = null
    private var multicastLock: WifiManager.MulticastLock? = null


    /** Перезапускає пошук: кожен перезапуск змушує систему заново опитати мережу. */
    fun start() {
        stop()
        val manager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
        nsd = manager
        // _uscan._tcp — сканери eSCL (Brother сам, Xerox — через шлюз AirSane на сервері).
        for (type in listOf("_ipp._tcp", "_ipps._tcp", "_uscan._tcp")) {
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

    fun stop() {
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
                manager.registerServiceInfoCallback(info, context.mainExecutor, callback)
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
        onFound(
            mapOf(
                "name" to info.serviceName,
                "host" to host,
                "port" to info.port,
                "tls" to (info.serviceType?.contains("_ipps") == true),
                "scanner" to (info.serviceType?.contains("_uscan") == true),
                "txt" to txt,
            ),
        )
    }

    // ------------------------------------------------------------------ multicast lock

    fun acquireMulticastLock() {
        if (multicastLock?.isHeld == true) return
        val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifi.createMulticastLock("kamidrop-mdns").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    fun releaseMulticastLock() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
    }
}

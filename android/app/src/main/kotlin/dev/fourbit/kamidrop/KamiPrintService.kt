package dev.fourbit.kamidrop

import android.print.PrintAttributes
import android.print.PrinterCapabilitiesInfo
import android.print.PrinterId
import android.print.PrinterInfo
import android.printservice.PrintJob
import android.printservice.PrintService
import android.printservice.PrinterDiscoverySession
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

/**
 * Служба друку Android: принтери KamiDrop у системному діалозі «Друк» будь-якого застосунку.
 * Сама нічого не друкує — запускає Dart-код застосунку (printServiceMain) у фоновому Flutter
 * без вікна: він шукає принтери й друкує PDF, який дає система, тим самим конвеєром.
 */
class KamiPrintService : PrintService() {
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var platformChannel: MethodChannel? = null
    private val nsd by lazy { NsdDiscovery(this) { found -> platformChannel?.invokeMethod("printerFound", found) } }

    private var known: List<Map<*, *>> = emptyList() // принтери від Dart (printerInfoMap)
    private val sessions = mutableListOf<Session>()
    private val jobs = HashMap<String, PrintJob>()

    override fun onCreate() {
        super.onCreate()
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)
        val e = FlutterEngine(applicationContext)
        // Той самий канал, що й у вікні застосунку: Dart-пошук просить NsdManager.
        platformChannel = MethodChannel(e.dartExecutor.binaryMessenger, "kamidrop/platform").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "startPrinterDiscovery" -> nsd.start()
                    "stopPrinterDiscovery" -> nsd.stop()
                    "acquireMulticastLock" -> nsd.acquireMulticastLock()
                    "releaseMulticastLock" -> nsd.releaseMulticastLock()
                    else -> return@setMethodCallHandler result.notImplemented()
                }
                result.success(null)
            }
        }
        channel = MethodChannel(e.dartExecutor.binaryMessenger, "kamidrop/printservice").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "printers" -> {
                        known = (call.arguments as? List<*>)?.filterIsInstance<Map<*, *>>() ?: emptyList()
                        sessions.forEach { it.publish() }
                    }
                    "jobState" -> onJobState(call.arguments as Map<*, *>)
                    else -> return@setMethodCallHandler result.notImplemented()
                }
                result.success(null)
            }
        }
        e.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "printServiceMain"),
        )
        engine = e
    }

    override fun onDestroy() {
        nsd.stop()
        nsd.releaseMulticastLock()
        engine?.destroy()
        engine = null
        super.onDestroy()
    }

    override fun onCreatePrinterDiscoverySession(): PrinterDiscoverySession = Session().also { sessions.add(it) }

    override fun onPrintJobQueued(job: PrintJob) {
        val info = job.info
        val printerId = info.printerId?.localId
        val data = job.document.data
        if (printerId == null || data == null) {
            job.fail(getString(R.string.print_no_document))
            return
        }
        // PDF від системи — у кеш: Dart відкриває його як звичайний файл.
        val dir = File(cacheDir, "printjobs").apply { mkdirs() }
        val file = File(dir, "${job.id}.pdf")
        try {
            data.use { pfd -> FileInputStream(pfd.fileDescriptor).use { input -> file.outputStream().use { input.copyTo(it) } } }
        } catch (e: Exception) {
            job.fail(e.message)
            return
        }
        val id = job.id.toString()
        jobs[id] = job
        job.start()
        val attrs = info.attributes
        channel?.invokeMethod(
            "print",
            mapOf(
                "jobId" to id,
                "printerId" to printerId,
                "path" to file.path,
                "copies" to info.copies,
                "color" to (attrs.colorMode == PrintAttributes.COLOR_MODE_COLOR),
                "duplex" to (attrs.duplexMode != PrintAttributes.DUPLEX_MODE_NONE),
                "ranges" to (info.pages ?: emptyArray()).map { listOf(it.start, it.end) },
            ),
        )
    }

    override fun onRequestCancelPrintJob(job: PrintJob) {
        channel?.invokeMethod("cancel", job.id.toString())
    }

    private fun onJobState(a: Map<*, *>) {
        val id = a["jobId"] as? String ?: return
        val job = jobs[id] ?: return
        val message = a["message"] as? String
        when (a["state"]) {
            "progress" -> if (message != null && job.isStarted) job.setStatus(message)
            "done" -> finish(id) { job.complete() }
            "failed" -> finish(id) { job.fail(message) }
            "cancelled" -> finish(id) { job.cancel() }
        }
    }

    private fun finish(id: String, action: () -> Unit) {
        jobs.remove(id)
        File(File(cacheDir, "printjobs"), "$id.pdf").delete()
        action()
    }

    private fun mils(mm: Any?): Int = (((mm as? Number)?.toDouble() ?: 0.0) / 25.4 * 1000).toInt()

    private fun toPrinterInfo(m: Map<*, *>): PrinterInfo {
        val id = generatePrinterId(m["id"] as String)
        val ready = m["ready"] == true
        val builder = PrinterInfo.Builder(
            id,
            m["name"] as String,
            if (ready) PrinterInfo.STATUS_IDLE else PrinterInfo.STATUS_UNAVAILABLE,
        )
        (m["model"] as? String)?.let { builder.setDescription(it) }
        if (ready) {
            val dpi = (m["dpi"] as? Number)?.toInt() ?: 300
            val color = m["color"] == true
            val margins = m["margins"] as? Map<*, *>
            val caps = PrinterCapabilitiesInfo.Builder(id)
                // Наш растр — A4 (media iso_a4); інші розміри поки не пропонуємо.
                .addMediaSize(PrintAttributes.MediaSize.ISO_A4, true)
                .addResolution(PrintAttributes.Resolution("dpi$dpi", "$dpi dpi", dpi, dpi), true)
                .setColorModes(
                    PrintAttributes.COLOR_MODE_MONOCHROME or (if (color) PrintAttributes.COLOR_MODE_COLOR else 0),
                    if (color) PrintAttributes.COLOR_MODE_COLOR else PrintAttributes.COLOR_MODE_MONOCHROME,
                )
                .setMinMargins(
                    PrintAttributes.Margins(mils(margins?.get("left")), mils(margins?.get("top")),
                        mils(margins?.get("right")), mils(margins?.get("bottom"))),
                )
            if (m["duplex"] == true) {
                caps.setDuplexModes(
                    PrintAttributes.DUPLEX_MODE_NONE or PrintAttributes.DUPLEX_MODE_LONG_EDGE,
                    PrintAttributes.DUPLEX_MODE_NONE,
                )
            }
            builder.setCapabilities(caps.build())
        }
        return builder.build()
    }

    /** Сесія пошуку системного діалогу: показуємо принтери, що їх знайшов Dart. */
    private inner class Session : PrinterDiscoverySession() {
        fun publish() {
            if (isDestroyed) return
            val infos = known.mapNotNull { runCatching { toPrinterInfo(it) }.getOrNull() }
            val ids = infos.map { it.id }.toSet()
            val gone: List<PrinterId> = printers.map { it.id }.filter { it !in ids }
            if (gone.isNotEmpty()) removePrinters(gone)
            addPrinters(infos)
        }

        override fun onStartPrinterDiscovery(priorityList: MutableList<PrinterId>) {
            publish()
            channel?.invokeMethod("refresh", null)
        }

        override fun onStopPrinterDiscovery() {}
        override fun onValidatePrinters(printerIds: MutableList<PrinterId>) = publish()
        override fun onStartPrinterStateTracking(printerId: PrinterId) = publish()
        override fun onStopPrinterStateTracking(printerId: PrinterId) {}
        override fun onDestroy() {
            sessions.remove(this)
        }
    }
}

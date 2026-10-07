package dev.fourbit.kamidrop

import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Нативна частина KamiDrop:
 *  - міст до пошуку принтерів і сканерів (NsdDiscovery — спільний зі службою друку);
 *  - прийом файлів через «Поділитися → KamiDrop» і «Відкрити за допомогою»;
 *  - вибір фото з галереї (системний Photo Picker, одне або кілька);
 *  - версія застосунку й встановлення оновлення (PackageInstaller);
 *  - «Поділитися» і «Зберегти в Завантаження» для сканів.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingSharedPath: String? = null
    private var pendingPick: MethodChannel.Result? = null
    private var pickPhotoWord: String? = null // «Фото» / «Photo» — мовою застосунку

    private val nsdDiscovery by lazy { NsdDiscovery(this) { found -> channel?.invokeMethod("printerFound", found) } }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingSharedPath = extractSharedFile(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kamidrop/platform").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "startPrinterDiscovery" -> {
                        nsdDiscovery.start()
                        result.success(null)
                    }
                    "stopPrinterDiscovery" -> {
                        nsdDiscovery.stop()
                        result.success(null)
                    }
                    "acquireMulticastLock" -> {
                        nsdDiscovery.acquireMulticastLock()
                        result.success(null)
                    }
                    "releaseMulticastLock" -> {
                        nsdDiscovery.releaseMulticastLock()
                        result.success(null)
                    }
                    "takeSharedFile" -> {
                        result.success(pendingSharedPath)
                        pendingSharedPath = null
                    }
                    "pickImages" -> {
                        pickPhotoWord = call.argument<String>("photoWord")
                        pickImages(result)
                    }
                    "appInfo" -> result.success(appInfo())
                    "openPrintSettings" -> {
                        startActivity(Intent(Settings.ACTION_PRINT_SETTINGS))
                        result.success(null)
                    }
                    "installApk" -> result.success(installApk(call.arguments as String))
                    "shareFiles" -> {
                        shareFiles(call.argument<List<String>>("paths")!!, call.argument<String>("mime")!!)
                        result.success(null)
                    }
                    "saveToDownloads" -> result.success(
                        saveToDownloads(call.argument<String>("path")!!, call.argument<String>("name")!!,
                            call.argument<String>("mime")!!))
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        current = this
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
        val uris = mutableListOf<Uri>()
        if (resultCode == RESULT_OK && data != null) {
            val clip = data.clipData
            if (clip != null) {
                for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
            } else {
                data.data?.let { uris.add(it) }
            }
        }
        try {
            // Тека — лише під цей вибір: старі фото стираємо один раз, а не перед кожним.
            val dir = freshDir("picked")
            result.success(uris.map { copyToCache(it, dir, pickPhotoWord) })
        } catch (e: Exception) {
            result.error("pick", e.message, null)
        }
    }

    override fun onDestroy() {
        if (current === this) current = null
        nsdDiscovery.stop()
        nsdDiscovery.releaseMulticastLock()
        super.onDestroy()
    }


    // ------------------------------------------------------------------ скани

    /** «Поділитися» одним файлом або кількома (напр. сторінки скану в PNG). */
    private fun shareFiles(paths: List<String>, mime: String) {
        val uris = ArrayList(paths.map { FileProvider.getUriForFile(this, "$packageName.files", File(it)) })
        val send = if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris[0])
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
        }
        send.type = mime
        send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        startActivity(Intent.createChooser(send, null))
    }

    /** Копія в «Завантаження/KamiDrop». Повертає шлях для людини або null (Android < 10). */
    private fun saveToDownloads(path: String, name: String, mime: String): String? {
        if (Build.VERSION.SDK_INT < 29) return null
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/KamiDrop")
        }
        val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return null
        contentResolver.openOutputStream(uri)!!.use { out -> File(path).inputStream().use { it.copyTo(out) } }
        return "${Environment.DIRECTORY_DOWNLOADS}/KamiDrop/$name"
    }

    // ------------------------------------------------------------------ оновлення

    private fun appInfo(): Map<String, Any> {
        val info = packageManager.getPackageInfo(packageName, 0)
        @Suppress("DEPRECATION")
        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
        return mapOf(
            "versionName" to (info.versionName ?: "0"),
            "versionCode" to code,
            "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: ""),
        )
    }

    /**
     * Ставить APK поверх себе. Повертає "permission", якщо спершу треба дозволити KamiDrop
     * встановлювати застосунки (відкриваємо відповідні налаштування), інакше "started".
     */
    private fun installApk(path: String): String {
        if (!packageManager.canRequestPackageInstalls()) {
            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
            return "permission"
        }
        val installer = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(packageName)
            // Android 12+: застосунок може оновити сам себе без зайвого вікна (якщо система дозволить).
            if (Build.VERSION.SDK_INT >= 31) setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }
        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            val apk = File(path)
            session.openWrite("kamidrop.apk", 0, apk.length()).use { out ->
                apk.inputStream().use { it.copyTo(out) }
                session.fsync(out)
            }
            val status = Intent(this, UpdateReceiver::class.java)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
            session.commit(PendingIntent.getBroadcast(this, sessionId, status, flags).intentSender)
        }
        return "started"
    }

    // ------------------------------------------------------------------ фото з галереї

    /** Android 13+ — системний Photo Picker (без дозволів); раніше — звичайний вибір зображень. */
    private fun pickImages(result: MethodChannel.Result) {
        pendingPick?.success(emptyList<String>()) // попередній вибір так і не завершився
        pendingPick = result
        val intent = if (Build.VERSION.SDK_INT >= 33) {
            Intent(MediaStore.ACTION_PICK_IMAGES).setType("image/*")
                .putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, minOf(MAX_PICK, MediaStore.getPickImagesMaxLimit()))
        } else {
            Intent(Intent.ACTION_GET_CONTENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE)
                .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
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
            copyToCache(uri, freshDir("shared"))
        } catch (e: Exception) {
            null
        }
    }

    /** Порожня тека в кеші: там лежать лише файли останнього отримання. */
    private fun freshDir(name: String): File = File(cacheDir, name).apply {
        mkdirs()
        listFiles()?.forEach { it.delete() }
    }

    /** Копіює вміст [uri] у [dir] під зрозумілою унікальною назвою. */
    private fun copyToCache(uri: Uri, dir: File, photoWord: String? = null): String {
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
                "${photoWord ?: getString(R.string.photo)} ${SimpleDateFormat("dd.MM.yyyy HH:mm", Locale.ROOT).format(Date(taken))}.$ext"
            base.all { it.isDigit() } -> "${photoWord ?: getString(R.string.photo)}.$ext"
            else -> "$base.$ext"
        }
        var out = File(dir, fileName)
        var n = 2
        while (out.exists()) out = File(dir, "${fileName.substringBeforeLast('.')} ($n).$ext").also { n++ }
        contentResolver.openInputStream(uri)!!.use { input ->
            out.outputStream().use { output -> input.copyTo(output) }
        }
        return out.absolutePath
    }

    companion object {
        @Volatile private var current: MainActivity? = null

        /** Помилку встановлення — у застосунок, якщо він відкритий. */
        fun reportUpdateError(message: String) {
            val activity = current ?: return
            activity.runOnUiThread { activity.channel?.invokeMethod("updateError", message) }
        }

        private const val REQUEST_PICK_IMAGE = 4201
        private const val MAX_PICK = 20
    }
}

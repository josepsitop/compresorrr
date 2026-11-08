package __PKG__

import android.Manifest
import android.app.ActivityManager
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.MediaCodecList
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var shareChannel: MethodChannel? = null
    private var pending: List<String>? = null
    private var dartReady = false
    private var permResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        shareChannel = MethodChannel(messenger, "squeeze/share")
        shareChannel?.setMethodCallHandler { call, result ->
            if (call.method == "initial") {
                dartReady = true
                result.success(pending)
                pending = null
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(messenger, "squeeze/system").setMethodCallHandler { call, result -> onSystem(call, result) }
        handleShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShare(intent)
    }

    // ------------------------------------------------------------ compartir hacia Squeeze
    @Suppress("DEPRECATION")
    private fun handleShare(i: Intent?) {
        if (i == null) return
        val uris = ArrayList<Uri>()
        if (i.action == Intent.ACTION_SEND) {
            val u = i.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            if (u != null) uris.add(u)
        } else if (i.action == Intent.ACTION_SEND_MULTIPLE) {
            val l = i.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            if (l != null) uris.addAll(l)
        }
        if (uris.isEmpty()) return
        i.action = null // evita procesar lo mismo otra vez al girar la pantalla
        Thread {
            val paths = ArrayList<String>()
            for (u in uris) {
                try {
                    val p = copyToCache(u)
                    if (p != null) paths.add(p)
                } catch (e: Exception) {
                }
            }
            runOnUiThread {
                if (paths.isNotEmpty()) {
                    if (dartReady) shareChannel?.invokeMethod("shared", paths) else pending = paths
                }
            }
        }.start()
    }

    private fun copyToCache(uri: Uri): String? {
        var name = "archivo"
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val n = c.getString(0)
                if (n != null) name = n.replace("/", "_")
            }
        }
        val dir = File(cacheDir, "shared")
        dir.mkdirs()
        var f = File(dir, name)
        var k = 2
        while (f.exists()) {
            f = File(dir, "${k}_$name")
            k++
        }
        val input = contentResolver.openInputStream(uri) ?: return null
        input.use { ins -> f.outputStream().use { out -> ins.copyTo(out) } }
        return f.absolutePath
    }

    // ------------------------------------------------------------ sistema
    private fun onSystem(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "device" -> {
                val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                val mi = ActivityManager.MemoryInfo()
                am.getMemoryInfo(mi)
                var hevc = false
                var h264 = false
                try {
                    for (c in MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos) {
                        if (!c.isEncoder) continue
                        val hw = if (Build.VERSION.SDK_INT >= 29) c.isHardwareAccelerated
                        else !(c.name.startsWith("OMX.google") || c.name.startsWith("c2.android"))
                        if (!hw) continue
                        for (t in c.supportedTypes) {
                            if (t.equals("video/hevc", true)) hevc = true
                            if (t.equals("video/avc", true)) h264 = true
                        }
                    }
                } catch (e: Exception) {
                }
                val m = HashMap<String, Any>()
                m["is64"] = android.os.Process.is64Bit()
                m["ramMb"] = mi.totalMem / 1048576L
                m["cores"] = Runtime.getRuntime().availableProcessors()
                m["sdk"] = Build.VERSION.SDK_INT
                m["hevcHw"] = hevc
                m["h264Hw"] = h264
                m["model"] = Build.MODEL ?: ""
                result.success(m)
            }
            "charging" -> {
                val i = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                val st = i?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
                val plugged = i?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
                result.success(
                    plugged != 0 || st == BatteryManager.BATTERY_STATUS_CHARGING ||
                        st == BatteryManager.BATTERY_STATUS_FULL
                )
            }
            "serviceStart", "serviceUpdate" -> {
                val i = Intent(this, SqueezeService::class.java)
                i.putExtra("text", call.argument<String>("text") ?: "Comprimiendo…")
                i.putExtra("progress", call.argument<Int>("progress") ?: -1)
                if (call.method == "serviceStart" && Build.VERSION.SDK_INT >= 33 &&
                    checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                ) {
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 71)
                }
                try {
                    if (Build.VERSION.SDK_INT >= 26) startForegroundService(i) else startService(i)
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
            "serviceStop" -> {
                try {
                    stopService(Intent(this, SqueezeService::class.java))
                } catch (e: Exception) {
                }
                result.success(true)
            }
            "videoPermission" -> {
                val perm = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_VIDEO
                else Manifest.permission.READ_EXTERNAL_STORAGE
                if (checkSelfPermission(perm) == PackageManager.PERMISSION_GRANTED) {
                    result.success(true)
                } else {
                    permResult = result
                    requestPermissions(arrayOf(perm), 72)
                }
            }
            "heaviest" -> {
                val limit = call.argument<Int>("limit") ?: 40
                val out = ArrayList<Map<String, Any?>>()
                try {
                    val proj = arrayOf(
                        MediaStore.Video.Media._ID,
                        MediaStore.Video.Media.DISPLAY_NAME,
                        MediaStore.Video.Media.SIZE,
                        MediaStore.Video.Media.DURATION,
                        MediaStore.Video.Media.DATA
                    )
                    val cur = contentResolver.query(
                        MediaStore.Video.Media.EXTERNAL_CONTENT_URI, proj, null, null,
                        MediaStore.Video.Media.SIZE + " DESC"
                    )
                    cur?.use { c ->
                        var n = 0
                        while (c.moveToNext() && n < limit) {
                            val id = c.getLong(0)
                            val uri = ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id)
                            val row = HashMap<String, Any?>()
                            row["uri"] = uri.toString()
                            row["name"] = c.getString(1)
                            row["size"] = c.getLong(2)
                            row["duration"] = c.getLong(3)
                            row["path"] = c.getString(4)
                            out.add(row)
                            n++
                        }
                    }
                } catch (e: Exception) {
                }
                result.success(out)
            }
            "copyUri" -> {
                val u = call.argument<String>("uri")
                Thread {
                    val p = try {
                        if (u == null) null else copyToCache(Uri.parse(u))
                    } catch (e: Exception) {
                        null
                    }
                    runOnUiThread { result.success(p) }
                }.start()
            }
            else -> result.notImplemented()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 72) {
            permResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            permResult = null
        }
    }
}

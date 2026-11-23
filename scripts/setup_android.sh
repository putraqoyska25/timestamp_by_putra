#!/usr/bin/env bash
set -euo pipefail

echo "=== Memulai setup proyek Android untuk timestamp_by_putra ==="

MANIFEST_PATH="android/app/src/main/AndroidManifest.xml"
if [ ! -f "$MANIFEST_PATH" ]; then
  echo "AndroidManifest.xml belum ada, menjalankan flutter create --platforms=android --org com.putra --project-name timestamp_by_putra . ..."
  flutter create --platforms=android --org com.putra --project-name timestamp_by_putra .
fi

if [ -f "$MANIFEST_PATH" ]; then
  python3 - <<'PY'
from pathlib import Path

path = Path("android/app/src/main/AndroidManifest.xml")
content = path.read_text(encoding="utf-8")

required_perms = [
    '<uses-permission android:name="android.permission.CAMERA" />',
    '<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />',
    '<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />',
    '<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />',
    '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />',
    '<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />',
    '<uses-permission android:name="android.permission.RECORD_AUDIO" />',
]

missing = [p for p in required_perms if p.split('"')[1] not in content]
if missing and "</manifest>" in content:
    injection = "".join(f"    {p}\n" for p in missing)
    content = content.replace("</manifest>", f"{injection}</manifest>", 1)
    path.write_text(content, encoding="utf-8")
    print(f"Berhasil menyuntikkan {len(missing)} izin ke AndroidManifest.xml")
else:
    print("Semua izin di AndroidManifest.xml sudah lengkap")
PY
else
  echo "ERROR: $MANIFEST_PATH tidak ditemukan!"
  exit 1
fi

MAIN_ACTIVITY_KT="$(find android/app/src/main -name 'MainActivity.kt' 2>/dev/null | head -n 1 || true)"
if [ -n "$MAIN_ACTIVITY_KT" ] && [ -f "$MAIN_ACTIVITY_KT" ]; then
  python3 - "$MAIN_ACTIVITY_KT" <<'PY'
import sys
from pathlib import Path

kt_path = Path(sys.argv[1])
pkg_name = "com.putra.timestamp_by_putra"

kotlin_code = """package __PKG__

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "timestamp_by_putra/media_store"
    private val brightnessChannelName = "timestamp_by_putra/screen_brightness"
    private val reqMediaCode = 7001
    private val reqTrashCode = 7002

    private var pendingPermResult: MethodChannel.Result? = null
    private var pendingTrashResult: MethodChannel.Result? = null
    private var pendingTrashUriCount: Int = 0
    private var pendingTrashPaths: List<String> = emptyList()

    private fun setKeepScreenOnFlag(enabled: Boolean) {
        runOnUiThread {
            if (enabled) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setKeepScreenOnFlag(true)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, brightnessChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setMaxBrightness" -> {
                        runOnUiThread {
                            val attrs = window.attributes
                            attrs.screenBrightness = 1.0f
                            window.attributes = attrs
                            result.success(true)
                        }
                    }
                    "restoreBrightness" -> {
                        runOnUiThread {
                            val attrs = window.attributes
                            attrs.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                            window.attributes = attrs
                            result.success(true)
                        }
                    }
                    "setKeepScreenOn" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        setKeepScreenOnFlag(enabled)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestMediaPermissions" -> requestMediaPermissions(result)
                    "getAllImages" -> result.success(queryAllImagePaths())
                    "moveToTrash" -> {
                        val rawPaths = call.argument<List<*>>("paths")
                        val paths = rawPaths
                            ?.mapNotNull { it?.toString()?.trim() }
                            ?.filter { it.isNotEmpty() }
                            ?: emptyList()
                        movePathsToTrash(paths, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        setKeepScreenOnFlag(false)
        super.onDestroy()
    }

    private fun requiredMediaPermissions(): Array<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
        } else {
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
    }

    private fun hasAllMediaPermissions(): Boolean {
        return requiredMediaPermissions().all { perm ->
            ContextCompat.checkSelfPermission(this, perm) ==
                PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestMediaPermissions(result: MethodChannel.Result) {
        if (hasAllMediaPermissions()) {
            result.success(true)
            return
        }
        if (pendingPermResult != null) {
            result.error("IN_PROGRESS", "Permintaan izin sedang berjalan", null)
            return
        }
        pendingPermResult = result
        ActivityCompat.requestPermissions(
            this,
            requiredMediaPermissions(),
            reqMediaCode,
        )
    }

    private fun queryAllImagePaths(): List<String> {
        if (!hasAllMediaPermissions()) return emptyList()

        val list = mutableListOf<String>()
        val seen = HashSet<String>()
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

        val projection = arrayOf(MediaStore.Images.Media.DATA)
        val sortOrder = "${MediaStore.Images.Media.DATE_MODIFIED} DESC"

        try {
            contentResolver.query(collection, projection, null, null, sortOrder)
                ?.use { cursor ->
                    val dataCol = cursor.getColumnIndex(MediaStore.Images.Media.DATA)
                    if (dataCol >= 0) {
                        while (cursor.moveToNext()) {
                            val path = cursor.getString(dataCol)?.trim() ?: ""
                            if (path.isNotEmpty() && seen.add(path) && File(path).exists()) {
                                list.add(path)
                            }
                        }
                    }
                }
        } catch (_: Exception) {
        }
        return list
    }

    private fun movePathsToTrash(paths: List<String>, result: MethodChannel.Result) {
        if (paths.isEmpty()) {
            result.success(
                mapOf(
                    "movedCount" to 0,
                    "unresolvedPaths" to emptyList<String>(),
                )
            )
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val uris = mutableListOf<Uri>()
            val unresolved = mutableListOf<String>()
            val collection = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)

            for (p in paths) {
                val uri = findImageUriByPath(collection, p)
                if (uri != null) {
                    uris.add(uri)
                } else {
                    unresolved.add(p)
                }
            }

            if (uris.isNotEmpty()) {
                try {
                    val pendingIntent = MediaStore.createTrashRequest(
                        contentResolver,
                        uris,
                        true,
                    )
                    pendingTrashResult = result
                    pendingTrashUriCount = uris.size
                    pendingTrashPaths = unresolved
                    ActivityCompat.startIntentSenderForResult(
                        this,
                        pendingIntent.intentSender,
                        reqTrashCode,
                        null,
                        0,
                        0,
                        0,
                        null,
                    )
                    return
                } catch (_: Exception) {
                }
            }
        }

        var moved = 0
        val remaining = mutableListOf<String>()
        for (p in paths) {
            try {
                val f = File(p)
                if (f.exists() && f.delete()) {
                    moved++
                } else {
                    remaining.add(p)
                }
            } catch (_: Exception) {
                remaining.add(p)
            }
        }
        result.success(
            mapOf(
                "movedCount" to moved,
                "unresolvedPaths" to remaining,
            )
        )
    }

    private fun findImageUriByPath(
        collection: Uri,
        filePath: String,
    ): Uri? {
        val projection = arrayOf(MediaStore.Images.Media._ID)
        val selection = "${MediaStore.Images.Media.DATA} = ?"
        val args = arrayOf(filePath)
        contentResolver.query(collection, projection, selection, args, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val id = cursor.getLong(
                        cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
                    )
                    return ContentUris.withAppendedId(collection, id)
                }
            }
        return null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == reqMediaCode) {
            val granted = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingPermResult?.success(granted)
            pendingPermResult = null
        }
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == reqTrashCode) {
            val res = pendingTrashResult
            val uriCount = pendingTrashUriCount
            val rem = pendingTrashPaths
            pendingTrashResult = null
            pendingTrashUriCount = 0
            pendingTrashPaths = emptyList()
            if (res != null) {
                if (resultCode == Activity.RESULT_OK) {
                    res.success(
                        mapOf(
                            "movedCount" to uriCount,
                            "unresolvedPaths" to emptyList<String>(),
                        )
                    )
                } else {
                    res.success(
                        mapOf(
                            "movedCount" to 0,
                            "unresolvedPaths" to rem,
                        )
                    )
                }
            }
        }
    }
}
""".replace("__PKG__", pkg_name)

kt_path.write_text(kotlin_code, encoding="utf-8")
print(f"Berhasil menulis MainActivity.kt ({kt_path}) dengan package {pkg_name}")
PY
else
  echo "PERINGATAN: MainActivity.kt tidak ditemukan di android/app/src/main"
fi

echo "=== Selesai setup Android ==="

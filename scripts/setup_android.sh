#!/usr/bin/env bash
set -euo pipefail

echo "=== Memulai setup proyek Android untuk timestamp_by_putra ==="

MANIFEST_PATH="android/app/src/main/AndroidManifest.xml"
if [ ! -f "$MANIFEST_PATH" ]; then
  echo "AndroidManifest.xml belum ada, menjalankan flutter create --platforms=android --org com.putra --project-name timestamp_by_putra . ..."
  flutter create --platforms=android --org com.putra --project-name timestamp_by_putra .
fi

if [ -f "$MANIFEST_PATH" ]; then
  python3 - << 'PY'
from pathlib import Path
import re

path = Path("android/app/src/main/AndroidManifest.xml")
content = path.read_text(encoding="utf-8")

if "xmlns:tools=" not in content and "<manifest" in content:
    content = content.replace(
        "<manifest",
        '<manifest xmlns:tools="http://schemas.android.com/tools"',
        1,
    )

content = re.sub(
    r'[ \t]*<uses-permission\b[^>]*android\.permission\.WRITE_EXTERNAL_STORAGE[^>]*/>\s*\n?',
    '',
    content,
    flags=re.DOTALL,
)

content = re.sub(
    r'(android:name="android\.permission\.WRITE_EXTERNAL_STORAGE"[^>]*android:maxSdkVersion=")29(")',
    r'\g<1>28\g<2>',
    content,
)

write_perm = (
    '<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" '
    'android:maxSdkVersion="28" tools:replace="android:maxSdkVersion" />'
)

if "</manifest>" in content:
    content = content.replace("</manifest>", f"    {write_perm}\n</manifest>", 1)

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
print("Berhasil menormalkan WRITE_EXTERNAL_STORAGE (maxSdkVersion=28 + tools:replace) dan izin AndroidManifest.xml")
PY
else
  echo "ERROR: $MANIFEST_PATH tidak ditemukan!"
  exit 1
fi

MAIN_ACTIVITY_KT="$(find android/app/src/main -name 'MainActivity.kt' 2>/dev/null | head -n 1 || true)"
if [ -n "$MAIN_ACTIVITY_KT" ] && [ -f "$MAIN_ACTIVITY_KT" ]; then
  python3 - "$MAIN_ACTIVITY_KT" << 'PY'
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
import android.media.MediaScannerConnection
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
    private val reqDeleteCode = 7002

    private var pendingPermResult: MethodChannel.Result? = null
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var pendingDeleteUriCount: Int = 0
    private var pendingDirectDeletedCount: Int = 0
    private var pendingDeletePaths: ArrayList<String> = arrayListOf()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, brightnessChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setKeepScreenOn" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                            result.success(true)
                        }
                    }
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
                        val paths = arrayListOf<String>()
                        if (rawPaths != null) {
                            for (item in rawPaths) {
                                val s = item?.toString()?.trim() ?: ""
                                if (s.isNotEmpty()) {
                                    paths.add(s)
                                }
                            }
                        }
                        deletePathsPermanently(paths, result)
                    }
                    else -> result.notImplemented()
                }
            }
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

    private fun queryAllImagePaths(): ArrayList<Any> {
        val list = arrayListOf<Any>()
        if (!hasAllMediaPermissions()) return list

        val seen = HashSet<String>()
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

        val projection = arrayOf(
            MediaStore.Images.Media.DATA,
            MediaStore.Images.Media.DATE_MODIFIED,
        )
        val sortOrder = "${MediaStore.Images.Media.DATE_MODIFIED} DESC"

        try {
            contentResolver.query(collection, projection, null, null, sortOrder)
                ?.use { cursor ->
                    val dataCol = cursor.getColumnIndex(MediaStore.Images.Media.DATA)
                    val modCol = cursor.getColumnIndex(MediaStore.Images.Media.DATE_MODIFIED)
                    if (dataCol >= 0) {
                        while (cursor.moveToNext()) {
                            val path = cursor.getString(dataCol)?.trim() ?: ""
                            if (path.isNotEmpty() && seen.add(path) && File(path).exists()) {
                                val modSec = if (modCol >= 0) cursor.getLong(modCol) else 0L
                                val entry = HashMap<String, Any>()
                                entry["path"] = path
                                entry["dateModified"] = modSec
                                list.add(entry)
                            }
                        }
                    }
                }
        } catch (_: Exception) {
        }
        return list
    }

    private fun deletePathsPermanently(paths: ArrayList<String>, result: MethodChannel.Result) {
        if (paths.isEmpty()) {
            val resMap = HashMap<String, Any>()
            resMap["movedCount"] = 0
            resMap["unresolvedPaths"] = arrayListOf<String>()
            result.success(resMap)
            return
        }

        var directDeleted = 0
        val needsSystemDialogPaths = arrayListOf<String>()
        val needsSystemDialogUris = arrayListOf<Uri>()
        val unresolved = arrayListOf<String>()
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

        for (p in paths) {
            val uri = findImageUriByPath(collection, p)
            val file = File(p)
            var deletedDirectly = false

            if (file.exists()) {
                try {
                    if (file.delete()) {
                        deletedDirectly = true
                    }
                } catch (_: Exception) {
                }
            }

            if (deletedDirectly) {
                directDeleted++
                if (uri != null) {
                    try {
                        contentResolver.delete(uri, null, null)
                    } catch (_: Exception) {
                    }
                }
                MediaScannerConnection.scanFile(this, arrayOf(p), null, null)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && uri != null) {
                needsSystemDialogUris.add(uri)
                needsSystemDialogPaths.add(p)
            } else if (!file.exists()) {
                if (uri != null) {
                    try {
                        contentResolver.delete(uri, null, null)
                    } catch (_: Exception) {
                    }
                }
                directDeleted++
            } else {
                unresolved.add(p)
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && needsSystemDialogUris.isNotEmpty()) {
            try {
                val pendingIntent = MediaStore.createDeleteRequest(
                    contentResolver,
                    needsSystemDialogUris,
                )
                pendingDeleteResult = result
                pendingDeleteUriCount = needsSystemDialogUris.size
                pendingDirectDeletedCount = directDeleted
                pendingDeletePaths = needsSystemDialogPaths
                ActivityCompat.startIntentSenderForResult(
                    this,
                    pendingIntent.intentSender,
                    reqDeleteCode,
                    null,
                    0,
                    0,
                    0,
                    null,
                )
                return
            } catch (_: Exception) {
                unresolved.addAll(needsSystemDialogPaths)
            }
        } else {
            unresolved.addAll(needsSystemDialogPaths)
        }

        val resMap = HashMap<String, Any>()
        resMap["movedCount"] = directDeleted
        resMap["unresolvedPaths"] = unresolved
        result.success(resMap)
    }

    private fun findImageUriByPath(
        collection: Uri,
        filePath: String,
    ): Uri? {
        val candidates = linkedSetOf(filePath)
        if (filePath.startsWith("/storage/emulated/0/")) {
            candidates.add("/sdcard/" + filePath.removePrefix("/storage/emulated/0/"))
        } else if (filePath.startsWith("/sdcard/")) {
            candidates.add("/storage/emulated/0/" + filePath.removePrefix("/sdcard/"))
        }

        val projection = arrayOf(MediaStore.Images.Media._ID)
        for (candidate in candidates) {
            try {
                val selection = "${MediaStore.Images.Media.DATA} = ?"
                val args = arrayOf(candidate)
                contentResolver.query(collection, projection, selection, args, null)
                    ?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val id = cursor.getLong(
                                cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
                            )
                            return ContentUris.withAppendedId(collection, id)
                        }
                    }
            } catch (_: Exception) {
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val f = File(filePath)
                val name = f.name
                val parentPath = f.parent ?: ""
                val relDir = when {
                    parentPath.startsWith("/storage/emulated/0/") ->
                        parentPath.removePrefix("/storage/emulated/0/").trimEnd('/') + "/"
                    parentPath.startsWith("/sdcard/") ->
                        parentPath.removePrefix("/sdcard/").trimEnd('/') + "/"
                    else -> ""
                }
                if (name.isNotEmpty() && relDir.isNotEmpty()) {
                    val selection =
                        "${MediaStore.Images.Media.DISPLAY_NAME} = ? AND ${MediaStore.Images.Media.RELATIVE_PATH} = ?"
                    val args = arrayOf(name, relDir)
                    contentResolver.query(collection, projection, selection, args, null)
                        ?.use { cursor ->
                            if (cursor.moveToFirst()) {
                                val id = cursor.getLong(
                                    cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
                                )
                                return ContentUris.withAppendedId(collection, id)
                            }
                        }
                }
            } catch (_: Exception) {
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
        if (requestCode == reqDeleteCode) {
            val res = pendingDeleteResult
            val uriCount = pendingDeleteUriCount
            val directCount = pendingDirectDeletedCount
            val rem = pendingDeletePaths
            pendingDeleteResult = null
            pendingDeleteUriCount = 0
            pendingDirectDeletedCount = 0
            pendingDeletePaths = arrayListOf()
            if (res != null) {
                val resMap = HashMap<String, Any>()
                if (resultCode == Activity.RESULT_OK) {
                    resMap["movedCount"] = directCount + uriCount
                    resMap["unresolvedPaths"] = arrayListOf<String>()
                } else {
                    resMap["movedCount"] = directCount
                    resMap["unresolvedPaths"] = rem
                }
                res.success(resMap)
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

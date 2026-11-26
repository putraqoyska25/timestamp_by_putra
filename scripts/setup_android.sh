#!/usr/bin/env bash
set -euo pipefail

echo "=== Memulai konfigurasi Android & MainActivity untuk timestamp_by_putra ==="

MANIFEST_FILE="android/app/src/main/AndroidManifest.xml"
BUILD_GRADLE_APP="android/app/build.gradle"
BUILD_GRADLE_APP_KTS="android/app/build.gradle.kts"
MAIN_ACTIVITY_KT="android/app/src/main/kotlin/com/putra/timestamp_by_putra/MainActivity.kt"
ICON_SRC="assets/icon/app_icon.png"

mkdir -p "android/app/src/main/kotlin/com/putra/timestamp_by_putra"

if [ -f "$MANIFEST_FILE" ]; then
  python3 - "$MANIFEST_FILE" << 'PY'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
ET.register_namespace('android', 'http://schemas.android.com/apk/res/android')
ET.register_namespace('tools', 'http://schemas.android.com/tools')

ANDROID_NS = 'http://schemas.android.com/apk/res/android'
TOOLS_NS = 'http://schemas.android.com/tools'

tree = ET.parse(path)
root = tree.getroot()

desired_permissions = [
    ("android.permission.CAMERA", {}),
    ("android.permission.ACCESS_FINE_LOCATION", {}),
    ("android.permission.ACCESS_COARSE_LOCATION", {}),
    ("android.permission.RECORD_AUDIO", {}),
    ("android.permission.READ_MEDIA_IMAGES", {}),
    ("android.permission.READ_MEDIA_VIDEO", {}),
    ("android.permission.READ_MEDIA_VISUAL_USER_SELECTED", {}),
    ("android.permission.READ_EXTERNAL_STORAGE", {f"{{{ANDROID_NS}}}maxSdkVersion": "32"}),
    ("android.permission.WRITE_EXTERNAL_STORAGE", {
        f"{{{ANDROID_NS}}}maxSdkVersion": "28",
        f"{{{TOOLS_NS}}}replace": "android:maxSdkVersion",
    }),
]

existing_perms = {}
for elem in list(root.findall("uses-permission")):
    name = elem.attrib.get(f"{{{ANDROID_NS}}}name", "")
    if name:
        existing_perms[name] = elem

for perm_name, extra_attrs in desired_permissions:
    elem = existing_perms.get(perm_name)
    if elem is None:
        elem = ET.Element("uses-permission", {f"{{{ANDROID_NS}}}name": perm_name})
        root.insert(0, elem)
    for k, v in extra_attrs.items():
        elem.set(k, v)

tree.write(path, encoding="utf-8", xml_declaration=True)
PY
fi

for gradle_file in "$BUILD_GRADLE_APP" "$BUILD_GRADLE_APP_KTS"; do
  if [ -f "$gradle_file" ]; then
    python3 - "$gradle_file" << 'PY'
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

src = re.sub(r'\bcompileSdkVersion\s+\d+', 'compileSdkVersion 36', src)
src = re.sub(r'\bcompileSdk\s*=\s*\d+', 'compileSdk = 36', src)
src = re.sub(r'\bcompileSdk\s+\d+', 'compileSdk 36', src)
src = re.sub(r'\btargetSdkVersion\s+\d+', 'targetSdkVersion 36', src)
src = re.sub(r'\btargetSdk\s*=\s*\d+', 'targetSdk = 36', src)
src = re.sub(r'\btargetSdk\s+\d+', 'targetSdk 36', src)

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
PY
  fi
done

if [ -f "$ICON_SRC" ]; then
  python3 - "$ICON_SRC" << 'PY'
import os
import sys

src_path = sys.argv[1]
sizes = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

try:
    from PIL import Image, ImageOps
    base = Image.open(src_path).convert("RGBA")
    for folder, px in sizes.items():
        out_dir = os.path.join("android/app/src/main/res", folder)
        os.makedirs(out_dir, exist_ok=True)
        pad = max(1, int(round(px * 0.08)))
        inner_px = max(1, px - (pad * 2))
        fitted = ImageOps.contain(base, (inner_px, inner_px), Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (px, px), (255, 255, 255, 255))
        off_x = (px - fitted.width) // 2
        off_y = (px - fitted.height) // 2
        canvas.paste(fitted, (off_x, off_y), fitted)
        rgb_out = canvas.convert("RGB")
        for name in ("ic_launcher.png", "ic_launcher_round.png"):
            rgb_out.save(os.path.join(out_dir, name), format="PNG")
except Exception as e:
    print(f"Pillow tidak tersedia atau gagal, fallback copy: {e}")
    import shutil
    for folder in sizes:
        out_dir = os.path.join("android/app/src/main/res", folder)
        os.makedirs(out_dir, exist_ok=True)
        for name in ("ic_launcher.png", "ic_launcher_round.png"):
            shutil.copyfile(src_path, os.path.join(out_dir, name))
PY
fi

cat << 'EOF' > "$MAIN_ACTIVITY_KT"
package com.putra.timestamp_by_putra

import android.Manifest
import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentResolver
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.util.Size
import android.view.KeyEvent
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import kotlin.math.max
import kotlin.math.min

class MainActivity : FlutterActivity() {
    companion object {
        private const val MEDIA_CHANNEL = "timestamp_by_putra/media_store"
        private const val BRIGHTNESS_CHANNEL = "timestamp_by_putra/screen_brightness"
        private const val HARDWARE_CHANNEL = "timestamp_by_putra/hardware_keys"
        private const val REQ_MEDIA_PERMISSIONS = 9011
        private const val REQ_DELETE_REQUEST = 9012
    }

    private var mediaChannel: MethodChannel? = null
    private var hardwareChannel: MethodChannel? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var pendingDeleteAllTargets: List<Pair<String, Uri?>> = emptyList()
    private var pendingDeleteDirectPaths: List<String> = emptyList()
    private var savedBrightness: Float = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
    private var volumeShutterEnabled: Boolean = true

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        savedBrightness = window.attributes.screenBrightness
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        mediaChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
        mediaChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestMediaPermissions" -> {
                    if (hasAllMediaPermissions()) {
                        result.success(true)
                    } else {
                        if (pendingPermissionResult != null) {
                            result.success(hasAllMediaPermissions())
                            return@setMethodCallHandler
                        }
                        pendingPermissionResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            requiredMediaPermissions(),
                            REQ_MEDIA_PERMISSIONS,
                        )
                    }
                }

                "getAlbumFolders" -> {
                    Thread {
                        try {
                            val data = queryAlbumFoldersData()
                            runOnUiThread { result.success(data) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("ALBUM_ERROR", e.message, null)
                            }
                        }
                    }.start()
                }

                "getAllImages" -> {
                    val limitArg = (call.argument<Number>("limit")?.toInt() ?: 2500).coerceIn(1, 50000)
                    val bucketIdArg = call.argument<String>("bucketId")?.trim()?.takeIf { it.isNotEmpty() }
                    Thread {
                        try {
                            val data = queryAllImagesData(limit = limitArg, bucketId = bucketIdArg)
                            runOnUiThread { result.success(data) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("IMAGES_ERROR", e.message, null)
                            }
                        }
                    }.start()
                }

                "readImageBytes" -> {
                    val uriStr = call.argument<String>("contentUri")?.trim().orEmpty()
                    val pathStr = call.argument<String>("path")?.trim().orEmpty()
                    Thread {
                        try {
                            val bytes = loadImageBytes(uriStr = uriStr, pathStr = pathStr)
                            runOnUiThread { result.success(bytes) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("READ_BYTES_ERROR", e.message, null)
                            }
                        }
                    }.start()
                }

                "readImageThumbnail" -> {
                    val uriStr = call.argument<String>("contentUri")?.trim().orEmpty()
                    val pathStr = call.argument<String>("path")?.trim().orEmpty()
                    val maxSide = (call.argument<Number>("maxSide")?.toInt() ?: 320).coerceIn(64, 1600)
                    Thread {
                        try {
                            val bytes = loadThumbnailBytes(
                                uriStr = uriStr,
                                pathStr = pathStr,
                                maxSide = maxSide,
                            )
                            runOnUiThread { result.success(bytes) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("READ_THUMB_ERROR", e.message, null)
                            }
                        }
                    }.start()
                }

                "deletePermanently" -> {
                    val rawPaths = call.argument<List<*>>("paths").orEmpty()
                        .mapNotNull { it?.toString()?.trim()?.takeIf { s -> s.isNotEmpty() } }
                        .distinct()
                    val rawUris = call.argument<List<*>>("contentUris").orEmpty()
                        .mapNotNull { it?.toString()?.trim()?.takeIf { s -> s.isNotEmpty() } }
                        .distinct()

                    if (rawPaths.isEmpty() && rawUris.isEmpty()) {
                        result.success(
                            mapOf(
                                "deletedCount" to 0,
                                "unresolvedPaths" to emptyList<String>(),
                            ),
                        )
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            handlePermanentDelete(
                                paths = rawPaths,
                                contentUris = rawUris,
                                result = result,
                            )
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("DELETE_ERROR", e.message, null)
                            }
                        }
                    }.start()
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BRIGHTNESS_CHANNEL)
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
                            savedBrightness = window.attributes.screenBrightness
                            val attrs = window.attributes
                            attrs.screenBrightness = 1.0f
                            window.attributes = attrs
                            result.success(true)
                        }
                    }

                    "restoreBrightness" -> {
                        runOnUiThread {
                            val attrs = window.attributes
                            attrs.screenBrightness = savedBrightness
                            window.attributes = attrs
                            result.success(true)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        hardwareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HARDWARE_CHANNEL)
        hardwareChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setVolumeShutterEnabled" -> {
                    volumeShutterEnabled = call.argument<Boolean>("enabled") ?: true
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (volumeShutterEnabled &&
            (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            if (event?.repeatCount == 0) {
                hardwareChannel?.invokeMethod("onVolumeShutterPressed", null)
            }
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (volumeShutterEnabled &&
            (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            return true
        }
        return super.onKeyUp(keyCode, event)
    }

    private fun requiredMediaPermissions(): Array<String> {
        return when {
            Build.VERSION.SDK_INT >= 34 -> arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VIDEO,
                "android.permission.READ_MEDIA_VISUAL_USER_SELECTED",
            )
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VIDEO,
            )
            else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
    }

    private fun hasAllMediaPermissions(): Boolean {
        return when {
            Build.VERSION.SDK_INT >= 34 -> {
                val fullImages = ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.READ_MEDIA_IMAGES,
                ) == PackageManager.PERMISSION_GRANTED
                val partialSelected = ContextCompat.checkSelfPermission(
                    this,
                    "android.permission.READ_MEDIA_VISUAL_USER_SELECTED",
                ) == PackageManager.PERMISSION_GRANTED
                fullImages || partialSelected
            }
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> {
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.READ_MEDIA_IMAGES,
                ) == PackageManager.PERMISSION_GRANTED
            }
            else -> {
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.READ_EXTERNAL_STORAGE,
                ) == PackageManager.PERMISSION_GRANTED
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_MEDIA_PERMISSIONS) {
            val cb = pendingPermissionResult
            pendingPermissionResult = null
            cb?.success(hasAllMediaPermissions())
        }
    }

    private fun mediaCollectionUri(): Uri {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
    }

    private fun buildResolvedPath(
        rawData: String?,
        relPath: String?,
        displayName: String?,
    ): String {
        val trimmedData = rawData?.trim().orEmpty()
        if (trimmedData.isNotEmpty() && File(trimmedData).exists()) {
            return trimmedData
        }
        val cleanRel = relPath?.trim()?.trim('/')?.replace('\\', '/').orEmpty()
        val cleanName = displayName?.trim().orEmpty()
        if (cleanRel.isNotEmpty() && cleanName.isNotEmpty()) {
            val primaryRoot = Environment.getExternalStorageDirectory().absolutePath
            val candidate = "$primaryRoot/$cleanRel/$cleanName"
            if (File(candidate).exists()) {
                return candidate
            }
            return trimmedData.ifEmpty { candidate }
        }
        return trimmedData
    }

    private fun queryAlbumFoldersData(): Map<String, Any?> {
        val collection = mediaCollectionUri()
        val projection = mutableListOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.MIME_TYPE,
            MediaStore.Images.Media.DATE_MODIFIED,
            MediaStore.Images.Media.DATE_ADDED,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            projection.add(MediaStore.Images.Media.BUCKET_ID)
            projection.add(MediaStore.Images.Media.BUCKET_DISPLAY_NAME)
            projection.add(MediaStore.Images.Media.RELATIVE_PATH)
        }
        @Suppress("DEPRECATION")
        projection.add(MediaStore.Images.Media.DATA)

        val selection = "${MediaStore.Images.Media.MIME_TYPE} LIKE ? OR ${MediaStore.Images.Media.MIME_TYPE} IS NULL"
        val selectionArgs = arrayOf("image/%")
        val sortOrder = "${MediaStore.Images.Media.DATE_MODIFIED} DESC, ${MediaStore.Images.Media._ID} DESC"

        var totalAllCount = 0
        var latestAllCoverPath = ""
        var latestAllCoverUri = ""

        data class FolderAcc(
            val bucketId: String,
            val bucketName: String,
            val relativePath: String,
            var count: Int,
            var coverPath: String,
            var coverUri: String,
        )

        val folderMap = LinkedHashMap<String, FolderAcc>()

        contentResolver.query(
            collection,
            projection.toTypedArray(),
            selection,
            selectionArgs,
            sortOrder,
        )?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val nameCol = cursor.getColumnIndex(MediaStore.Images.Media.DISPLAY_NAME)
            val dataCol = cursor.getColumnIndex(MediaStore.Images.Media.DATA)
            val modCol = cursor.getColumnIndex(MediaStore.Images.Media.DATE_MODIFIED)
            val addCol = cursor.getColumnIndex(MediaStore.Images.Media.DATE_ADDED)
            val bucketIdCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                cursor.getColumnIndex(MediaStore.Images.Media.BUCKET_ID)
            } else {
                -1
            }
            val bucketNameCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                cursor.getColumnIndex(MediaStore.Images.Media.BUCKET_DISPLAY_NAME)
            } else {
                -1
            }
            val relPathCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                cursor.getColumnIndex(MediaStore.Images.Media.RELATIVE_PATH)
            } else {
                -1
            }

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idCol)
                val itemUri = ContentUris.withAppendedId(collection, id)
                val dispName = if (nameCol >= 0) cursor.getString(nameCol) else null
                val rawData = if (dataCol >= 0) cursor.getString(dataCol) else null
                val relPath = if (relPathCol >= 0) cursor.getString(relPathCol) else null
                val resolvedPath = buildResolvedPath(rawData, relPath, dispName)

                if (resolvedPath.isEmpty() && itemUri.toString().isEmpty()) continue

                totalAllCount++
                if (latestAllCoverUri.isEmpty()) {
                    latestAllCoverUri = itemUri.toString()
                    latestAllCoverPath = resolvedPath
                }

                val bIdRaw = if (bucketIdCol >= 0) cursor.getString(bucketIdCol)?.trim().orEmpty() else ""
                val bNameRaw = if (bucketNameCol >= 0) cursor.getString(bucketNameCol)?.trim().orEmpty() else ""
                val cleanRel = relPath?.trim()?.replace('\\', '/').orEmpty()

                val fallbackBucketId = when {
                    bIdRaw.isNotEmpty() -> bIdRaw
                    cleanRel.isNotEmpty() -> "rel:$cleanRel"
                    resolvedPath.contains('/') -> "dir:${resolvedPath.substringBeforeLast('/')}"
                    else -> "root_images"
                }

                val fallbackBucketName = when {
                    bNameRaw.isNotEmpty() -> bNameRaw
                    cleanRel.trim('/').isNotEmpty() -> cleanRel.trim('/').substringAfterLast('/')
                    resolvedPath.contains('/') -> resolvedPath.substringBeforeLast('/').substringAfterLast('/')
                    else -> "Pictures"
                }

                val existing = folderMap[fallbackBucketId]
                if (existing == null) {
                    folderMap[fallbackBucketId] = FolderAcc(
                        bucketId = fallbackBucketId,
                        bucketName = fallbackBucketName,
                        relativePath = cleanRel,
                        count = 1,
                        coverPath = resolvedPath,
                        coverUri = itemUri.toString(),
                    )
                } else {
                    existing.count += 1
                }
            }
        }

        val foldersOut = folderMap.values.map { acc ->
            mapOf(
                "bucketId" to acc.bucketId,
                "bucketName" to acc.bucketName,
                "relativePath" to acc.relativePath,
                "count" to acc.count,
                "coverPath" to acc.coverPath,
                "coverUri" to acc.coverUri,
            )
        }

        return mapOf(
            "totalAllCount" to totalAllCount,
            "latestAllCoverPath" to latestAllCoverPath,
            "latestAllCoverUri" to latestAllCoverUri,
            "folders" to foldersOut,
        )
    }

    private fun queryAllImagesData(limit: Int, bucketId: String?): Map<String, Any?> {
        val collection = mediaCollectionUri()
        val projection = mutableListOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.MIME_TYPE,
            MediaStore.Images.Media.DATE_MODIFIED,
            MediaStore.Images.Media.DATE_ADDED,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            projection.add(MediaStore.Images.Media.BUCKET_ID)
            projection.add(MediaStore.Images.Media.RELATIVE_PATH)
        }
        @Suppress("DEPRECATION")
        projection.add(MediaStore.Images.Media.DATA)

        val whereClauses = mutableListOf(
            "(${MediaStore.Images.Media.MIME_TYPE} LIKE ? OR ${MediaStore.Images.Media.MIME_TYPE} IS NULL)",
        )
        val whereArgs = mutableListOf("image/%")

        val cleanBucketId = bucketId?.trim().orEmpty()
        if (cleanBucketId.isNotEmpty() &&
            !cleanBucketId.startsWith("rel:") &&
            !cleanBucketId.startsWith("dir:") &&
            cleanBucketId != "root_images" &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        ) {
            whereClauses.add("${MediaStore.Images.Media.BUCKET_ID} = ?")
            whereArgs.add(cleanBucketId)
        }

        val selection = whereClauses.joinToString(" AND ")
        val sortOrder = "${MediaStore.Images.Media.DATE_MODIFIED} DESC, ${MediaStore.Images.Media._ID} DESC"

        val items = ArrayList>(min(limit, 2500))
        var hasMore = false

        contentResolver.query(
            collection,
            projection.toTypedArray(),
            selection,
            whereArgs.toTypedArray(),
            sortOrder,
        )?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val nameCol = cursor.getColumnIndex(MediaStore.Images.Media.DISPLAY_NAME)
            val mimeCol = cursor.getColumnIndex(MediaStore.Images.Media.MIME_TYPE)
            val dataCol = cursor.getColumnIndex(MediaStore.Images.Media.DATA)
            val modCol = cursor.getColumnIndex(MediaStore.Images.Media.DATE_MODIFIED)
            val addCol = cursor.getColumnIndex(MediaStore.Images.Media.DATE_ADDED)
            val relPathCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                cursor.getColumnIndex(MediaStore.Images.Media.RELATIVE_PATH)
            } else {
                -1
            }

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idCol)
                val itemUri = ContentUris.withAppendedId(collection, id)
                val dispName = if (nameCol >= 0) cursor.getString(nameCol).orEmpty() else ""
                val mimeType = if (mimeCol >= 0) cursor.getString(mimeCol).orEmpty() else ""
                val rawData = if (dataCol >= 0) cursor.getString(dataCol) else null
                val relPath = if (relPathCol >= 0) cursor.getString(relPathCol) else null
                val resolvedPath = buildResolvedPath(rawData, relPath, dispName)

                if (cleanBucketId.startsWith("rel:")) {
                    val targetRel = cleanBucketId.removePrefix("rel:")
                    if (relPath?.trim()?.replace('\\', '/') != targetRel) continue
                } else if (cleanBucketId.startsWith("dir:")) {
                    val targetDir = cleanBucketId.removePrefix("dir:")
                    val parentDir = if (resolvedPath.contains('/')) {
                        resolvedPath.substringBeforeLast('/')
                    } else {
                        ""
                    }
                    if (parentDir != targetDir) continue
                } else if (cleanBucketId == "root_images") {
                    if (resolvedPath.contains('/')) continue
                }

                if (resolvedPath.isEmpty() && itemUri.toString().isEmpty()) continue

                if (items.size >= limit) {
                    hasMore = true
                    break
                }

                val modSec = when {
                    modCol >= 0 && cursor.getLong(modCol) > 0L -> cursor.getLong(modCol)
                    addCol >= 0 && cursor.getLong(addCol) > 0L -> cursor.getLong(addCol)
                    else -> System.currentTimeMillis() / 1000L
                }

                items.add(
                    mapOf(
                        "path" to resolvedPath,
                        "contentUri" to itemUri.toString(),
                        "displayName" to dispName,
                        "mimeType" to mimeType,
                        "dateModified" to modSec,
                    ),
                )
            }
        }

        return mapOf(
            "items" to items,
            "hasMore" to hasMore,
        )
    }

    private fun readStreamToBytes(stream: InputStream): ByteArray {
        val out = ByteArrayOutputStream(32768)
        val buf = ByteArray(16384)
        while (true) {
            val n = stream.read(buf)
            if (n <= 0) break
            out.write(buf, 0, n)
        }
        return out.toByteArray()
    }

    private fun loadImageBytes(uriStr: String, pathStr: String): ByteArray? {
        if (uriStr.isNotEmpty()) {
            try {
                val uri = Uri.parse(uriStr)
                contentResolver.openInputStream(uri)?.use { stream ->
                    val bytes = readStreamToBytes(stream)
                    if (bytes.isNotEmpty()) return bytes
                }
            } catch (_: Exception) {
            }
        }
        if (pathStr.isNotEmpty()) {
            try {
                val f = File(pathStr)
                if (f.exists() && f.length() > 0L) {
                    return f.readBytes()
                }
            } catch (_: Exception) {
            }
        }
        return null
    }

    private fun applyExifRotation(bitmap: Bitmap, exifDegree: Int): Bitmap {
        if (exifDegree == 0) return bitmap
        val m = Matrix()
        m.postRotate(exifDegree.toFloat())
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, m, true)
    }

    private fun readExifDegreeFromUriOrPath(uriStr: String, pathStr: String): Int {
        try {
            if (uriStr.isNotEmpty()) {
                contentResolver.openInputStream(Uri.parse(uriStr))?.use { ins ->
                    val exif = ExifInterface(ins)
                    return when (exif.getAttributeInt(
                        ExifInterface.TAG_ORIENTATION,
                        ExifInterface.ORIENTATION_NORMAL,
                    )) {
                        ExifInterface.ORIENTATION_ROTATE_90 -> 90
                        ExifInterface.ORIENTATION_ROTATE_180 -> 180
                        ExifInterface.ORIENTATION_ROTATE_270 -> 270
                        else -> 0
                    }
                }
            }
        } catch (_: Exception) {
        }
        if (pathStr.isNotEmpty()) {
            try {
                val exif = ExifInterface(pathStr)
                return when (exif.getAttributeInt(
                    ExifInterface.TAG_ORIENTATION,
                    ExifInterface.ORIENTATION_NORMAL,
                )) {
                    ExifInterface.ORIENTATION_ROTATE_90 -> 90
                    ExifInterface.ORIENTATION_ROTATE_180 -> 180
                    ExifInterface.ORIENTATION_ROTATE_270 -> 270
                    else -> 0
                }
            } catch (_: Exception) {
            }
        }
        return 0
    }

    private fun loadThumbnailBytes(uriStr: String, pathStr: String, maxSide: Int): ByteArray? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && uriStr.isNotEmpty()) {
            try {
                val bmp = contentResolver.loadThumbnail(
                    Uri.parse(uriStr),
                    Size(maxSide, maxSide),
                    null,
                )
                val out = ByteArrayOutputStream()
                bmp.compress(Bitmap.CompressFormat.JPEG, 82, out)
                return out.toByteArray()
            } catch (_: Exception) {
            }
        }

        val fullBytes = loadImageBytes(uriStr = uriStr, pathStr = pathStr) ?: return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(fullBytes, 0, fullBytes.size, bounds)
        val longest = max(bounds.outWidth, bounds.outHeight)
        var sample = 1
        while (longest / sample > maxSide * 2) {
            sample *= 2
        }
        val opts = BitmapFactory.Options().apply { inSampleSize = max(1, sample) }
        val decoded = BitmapFactory.decodeByteArray(fullBytes, 0, fullBytes.size, opts) ?: return null
        val deg = readExifDegreeFromUriOrPath(uriStr = uriStr, pathStr = pathStr)
        val oriented = applyExifRotation(decoded, deg)
        val scale = min(1.0f, maxSide.toFloat() / max(1, max(oriented.width, oriented.height)))
        val finalBmp = if (scale < 0.99f) {
            Bitmap.createScaledBitmap(
                oriented,
                max(1, (oriented.width * scale).toInt()),
                max(1, (oriented.height * scale).toInt()),
                true,
            )
        } else {
            oriented
        }
        val out = ByteArrayOutputStream()
        finalBmp.compress(Bitmap.CompressFormat.JPEG, 82, out)
        return out.toByteArray()
    }

    private fun resolveUriForPath(path: String): Uri? {
        if (path.isEmpty()) return null
        val collection = mediaCollectionUri()
        @Suppress("DEPRECATION")
        val projection = arrayOf(MediaStore.Images.Media._ID)
        @Suppress("DEPRECATION")
        val selection = "${MediaStore.Images.Media.DATA} = ?"
        contentResolver.query(
            collection,
            projection,
            selection,
            arrayOf(path),
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val id = cursor.getLong(0)
                return ContentUris.withAppendedId(collection, id)
            }
        }
        return null
    }

    private fun handlePermanentDelete(
        paths: List<String>,
        contentUris: List<String>,
        result: MethodChannel.Result,
    ) {
        var deletedCount = 0
        val unresolvedPaths = mutableListOf<String>()
        val targetPairs = LinkedHashMap<String, Pair<String, Uri?>>()

        for (uStr in contentUris) {
            val parsed = try {
                Uri.parse(uStr)
            } catch (_: Exception) {
                null
            }
            if (parsed != null) {
                targetPairs["uri:$uStr"] = Pair("", parsed)
            }
        }

        for (p in paths) {
            val existing = targetPairs.entries.firstOrNull { it.value.first == p }
            if (existing != null) continue
            val resolvedUri = resolveUriForPath(p)
            targetPairs["path:$p"] = Pair(p, resolvedUri)
        }

        val urisForApi30: MutableList<Uri> = mutableListOf()

        for ((_, pair) in targetPairs) {
            val path = pair.first
            val uri = pair.second

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                if (uri != null) {
                    urisForApi30.add(uri)
                } else if (path.isNotEmpty()) {
                    unresolvedPaths.add(path)
                }
                continue
            }

            var removed = false
            if (uri != null) {
                try {
                    val rows = contentResolver.delete(uri, null, null)
                    if (rows > 0) removed = true
                } catch (secEx: SecurityException) {
                    if (Build.VERSION.SDK_INT == Build.VERSION_CODES.Q &&
                        secEx is RecoverableSecurityException
                    ) {
                        pendingDeleteAllTargets = targetPairs.values.toList()
                        pendingDeleteDirectPaths = paths
                        pendingDeleteResult = result
                        runOnUiThread {
                            try {
                                ActivityCompat.startIntentSenderForResult(
                                    this,
                                    secEx.userAction.actionIntent.intentSender,
                                    REQ_DELETE_REQUEST,
                                    null,
                                    0,
                                    0,
                                    0,
                                    null,
                                )
                            } catch (_: Exception) {
                                pendingDeleteResult = null
                                result.success(
                                    mapOf(
                                        "deletedCount" to deletedCount,
                                        "unresolvedPaths" to unresolvedPaths,
                                    ),
                                )
                            }
                        }
                        return
                    }
                } catch (_: Exception) {
                }
            }

            if (!removed && path.isNotEmpty()) {
                try {
                    val f = File(path)
                    if (!f.exists() || f.delete()) {
                        removed = true
                    }
                } catch (_: Exception) {
                }
            }

            if (removed) {
                deletedCount++
            } else if (path.isNotEmpty()) {
                unresolvedPaths.add(path)
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && urisForApi30.isNotEmpty()) {
            try {
                val distinctUris = urisForApi30.distinct()
                val pendingIntent = MediaStore.createDeleteRequest(contentResolver, distinctUris)
                pendingDeleteAllTargets = targetPairs.values.toList()
                pendingDeleteDirectPaths = paths
                pendingDeleteResult = result
                runOnUiThread {
                    try {
                        ActivityCompat.startIntentSenderForResult(
                            this,
                            pendingIntent.intentSender,
                            REQ_DELETE_REQUEST,
                            null,
                            0,
                            0,
                            0,
                            null,
                        )
                    } catch (_: Exception) {
                        pendingDeleteResult = null
                        result.success(
                            mapOf(
                                "deletedCount" to 0,
                                "unresolvedPaths" to unresolvedPaths,
                            ),
                        )
                    }
                }
                return
            } catch (_: Exception) {
            }
        }

        runOnUiThread {
            result.success(
                mapOf(
                    "deletedCount" to deletedCount,
                    "unresolvedPaths" to unresolvedPaths,
                ),
            )
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_DELETE_REQUEST) {
            val cb = pendingDeleteResult
            val targets = pendingDeleteAllTargets
            val directPaths = pendingDeleteDirectPaths
            pendingDeleteResult = null
            pendingDeleteAllTargets = emptyList()
            pendingDeleteDirectPaths = emptyList()

            if (cb == null) return

            if (resultCode == Activity.RESULT_OK) {
                Thread {
                    var confirmedDeleted = 0
                    val stillRemaining = mutableListOf<String>()

                    for ((path, uri) in targets) {
                        var gone = false
                        if (uri != null) {
                            try {
                                contentResolver.delete(uri, null, null)
                            } catch (_: Exception) {
                            }
                            try {
                                contentResolver.query(uri, arrayOf(MediaStore.Images.Media._ID), null, null, null)?.use { c ->
                                    if (!c.moveToFirst()) gone = true
                                }
                            } catch (_: Exception) {
                                gone = true
                            }
                        }
                        if (path.isNotEmpty()) {
                            try {
                                val f = File(path)
                                if (f.exists()) {
                                    f.delete()
                                }
                                if (!f.exists()) gone = true
                            } catch (_: Exception) {
                            }
                        }
                        if (gone) {
                            confirmedDeleted++
                        } else if (path.isNotEmpty()) {
                            stillRemaining.add(path)
                        }
                    }

                    if (confirmedDeleted == 0 && targets.isNotEmpty()) {
                        confirmedDeleted = targets.size
                    }

                    for (p in directPaths) {
                        try {
                            val f = File(p)
                            if (f.exists() && !stillRemaining.contains(p)) {
                                stillRemaining.add(p)
                            }
                        } catch (_: Exception) {
                        }
                    }

                    runOnUiThread {
                        cb.success(
                            mapOf(
                                "deletedCount" to confirmedDeleted,
                                "unresolvedPaths" to stillRemaining.distinct(),
                            ),
                        )
                    }
                }.start()
            } else {
                cb.success(
                    mapOf(
                        "deletedCount" to 0,
                        "unresolvedPaths" to directPaths,
                    ),
                )
            }
        }
    }
}
EOF

chmod +x "$MAIN_ACTIVITY_KT"
echo "=== Selesai konfigurasi Android & MainActivity ==="

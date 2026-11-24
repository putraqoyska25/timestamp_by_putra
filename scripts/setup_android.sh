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

ICON_SRC="assets/icon/app_icon.png"
if [ -f "$ICON_SRC" ]; then
  python3 - "$ICON_SRC" << 'PY'
import shutil
import subprocess
import sys
from pathlib import Path

src = Path(sys.argv[1])
res_root = Path("android/app/src/main/res")
sizes = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

pil_ok = False
try:
    from PIL import Image, ImageOps
    pil_ok = True
except ImportError:
    pil_ok = False

if pil_ok:
    with Image.open(src) as im:
        rgb_im = im.convert("RGB")
        padded = ImageOps.expand(rgb_im, border=max(1, int(min(rgb_im.size) * 0.08)), fill=(255, 255, 255))
        for folder, px in sizes.items():
            out_dir = res_root / folder
            out_dir.mkdir(parents=True, exist_ok=True)
            resized = padded.resize((px, px), Image.Resampling.LANCZOS)
            for fname in ("ic_launcher.png", "ic_launcher_round.png"):
                target = out_dir / fname
                resized.save(target, format="PNG")
    print("Berhasil memasang app_icon.png ke seluruh folder mipmap-* via Pillow")
elif shutil.which("ffmpeg"):
    for folder, px in sizes.items():
        out_dir = res_root / folder
        out_dir.mkdir(parents=True, exist_ok=True)
        for fname in ("ic_launcher.png", "ic_launcher_round.png"):
            target = out_dir / fname
            subprocess.run(
                [
                    "ffmpeg", "-y", "-i", str(src),
                    "-vf", f"scale={px}:{px}:flags=lanczos",
                    str(target),
                ],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
    print("Berhasil memasang app_icon.png ke seluruh folder mipmap-* via ffmpeg")
else:
    for folder in sizes:
        out_dir = res_root / folder
        out_dir.mkdir(parents=True, exist_ok=True)
        for fname in ("ic_launcher.png", "ic_launcher_round.png"):
            shutil.copyfile(src, out_dir / fname)
    print("Pillow & ffmpeg tidak tersedia; menyalin app_icon.png langsung ke mipmap-*")
PY
else
  echo "PERINGATAN: $ICON_SRC tidak ditemukan, melewati pemasangan ikon kustom."
fi

MAIN_DART_PATH="lib/main.dart"
if [ -f "$MAIN_DART_PATH" ]; then
  python3 - "$MAIN_DART_PATH" << 'PY'
import sys
from pathlib import Path

dart_path = Path(sys.argv[1])
src = dart_path.read_text(encoding="utf-8")
fixed = src.replace("const SizedBox.height(12)", "const SizedBox(height: 12)")
if fixed != src:
    dart_path.write_text(fixed, encoding="utf-8")
    print("Berhasil memperbaiki 'const SizedBox.height(12)' menjadi 'const SizedBox(height: 12)' di lib/main.dart")
else:
    print("lib/main.dart sudah menggunakan 'const SizedBox(height: 12)'")
PY
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
                    "deletePermanently", "moveToTrash" -> {
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
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DATA,
            MediaStore.Images.Media.DATE_TAKEN,
            MediaStore.Images.Media.DATE_MODIFIED,
        )
        val sortOrder = "${MediaStore.Images.Media.DATE_MODIFIED} DESC, ${MediaStore.Images.Media._ID} DESC"

        try {
            contentResolver.query(
                collection,
                projection,
                null,
                null,
                sortOrder,
            )?.use { cursor ->
                val dataCol = cursor.getColumnIndex(MediaStore.Images.Media.DATA)
                val takenCol = cursor.getColumnIndex(MediaStore.Images.Media.DATE_TAKEN)
                val modCol = cursor.getColumnIndex(MediaStore.Images.Media.DATE_MODIFIED)

                while (cursor.moveToNext() && list.size < 2500) {
                    val path = if (dataCol >= 0) (cursor.getString(dataCol) ?: "").trim() else ""
                    if (path.isEmpty() || seen.contains(path)) continue
                    val takenMs = if (takenCol >= 0) cursor.getLong(takenCol) else 0L
                    val modSec = if (modCol >= 0) cursor.getLong(modCol) else 0L
                    val effectiveSec = when {
                        modSec > 0L -> modSec
                        takenMs > 0L -> takenMs / 1000L
                        else -> System.currentTimeMillis() / 1000L
                    }
                    seen.add(path)
                    list.add(
                        hashMapOf<String, Any>(
                            "path" to path,
                            "dateModified" to effectiveSec,
                        )
                    )
                }
            }
        } catch (_: Exception) {
        }

        return list
    }

    private fun resolveMediaUriForPath(path: String): Uri? {
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

        try {
            contentResolver.query(
                collection,
                arrayOf(MediaStore.Images.Media._ID),
                "${MediaStore.Images.Media.DATA} = ?",
                arrayOf(path),
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idCol = cursor.getColumnIndex(MediaStore.Images.Media._ID)
                    if (idCol >= 0) {
                        val id = cursor.getLong(idCol)
                        return ContentUris.withAppendedId(collection, id)
                    }
                }
            }
        } catch (_: Exception) {
        }

        return null
    }

    private fun deletePathsPermanently(
        paths: List<String>,
        result: MethodChannel.Result,
    ) {
        if (paths.isEmpty()) {
            result.success(
                hashMapOf<String, Any>(
                    "deletedCount" to 0,
                    "unresolvedPaths" to emptyList<String>(),
                )
            )
            return
        }

        var directDeleted = 0
        val urisToRequest = arrayListOf<Uri>()
        val unresolvedPaths = arrayListOf<String>()
        val scannedPaths = arrayListOf<String>()

        for (rawPath in paths) {
            val clean = rawPath.trim()
            if (clean.isEmpty()) continue
            scannedPaths.add(clean)

            var removed = false
            val f = File(clean)
            if (f.exists()) {
                try {
                    if (f.delete()) {
                        removed = true
                    }
                } catch (_: SecurityException) {
                    removed = false
                } catch (_: Exception) {
                    removed = false
                }
            }

            val uri = resolveMediaUriForPath(clean)
            if (!removed && uri != null) {
                try {
                    val rows = contentResolver.delete(uri, null, null)
                    if (rows > 0) {
                        removed = true
                    }
                } catch (_: SecurityException) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                        !urisToRequest.contains(uri)
                    ) {
                        urisToRequest.add(uri)
                    }
                } catch (_: Exception) {
                }
            }

            if (removed) {
                directDeleted++
            } else if (uri == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                unresolvedPaths.add(clean)
            }
        }

        if (scannedPaths.isNotEmpty()) {
            try {
                MediaScannerConnection.scanFile(
                    this,
                    scannedPaths.toTypedArray(),
                    null,
                    null,
                )
            } catch (_: Exception) {
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && urisToRequest.isNotEmpty()) {
            if (pendingDeleteResult != null) {
                result.error("IN_PROGRESS", "Penghapusan permanen sedang berjalan", null)
                return
            }
            try {
                val pendingIntent = MediaStore.createDeleteRequest(
                    contentResolver,
                    urisToRequest,
                )
                pendingDeleteResult = result
                pendingDeleteUriCount = urisToRequest.size
                pendingDirectDeletedCount = directDeleted
                pendingDeletePaths = unresolvedPaths
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
            }
        }

        result.success(
            hashMapOf<String, Any>(
                "deletedCount" to directDeleted,
                "unresolvedPaths" to unresolvedPaths,
            )
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == reqMediaCode) {
            val cb = pendingPermResult
            pendingPermResult = null
            cb?.success(hasAllMediaPermissions())
        }
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == reqDeleteCode) {
            val cb = pendingDeleteResult
            val uriCount = pendingDeleteUriCount
            val directDeleted = pendingDirectDeletedCount
            val unresolved = pendingDeletePaths

            pendingDeleteResult = null
            pendingDeleteUriCount = 0
            pendingDirectDeletedCount = 0
            pendingDeletePaths = arrayListOf()

            val granted = resultCode == Activity.RESULT_OK
            val totalDeleted = if (granted) directDeleted + uriCount else directDeleted
            cb?.success(
                hashMapOf<String, Any>(
                    "deletedCount" to totalDeleted,
                    "unresolvedPaths" to unresolved,
                )
            )
        }
    }
}
""".replace("__PKG__", pkg_name)

kt_path.write_text(kotlin_code, encoding="utf-8")
print(f"Berhasil memperbarui {kt_path}")
PY
fi

echo "=== Setup Android selesai ==="

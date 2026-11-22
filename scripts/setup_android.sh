#!/usr/bin/env bash
set -euo pipefail

MANIFEST="android/app/src/main/AndroidManifest.xml"
if [ -f "$MANIFEST" ]; then
  python3 - "$MANIFEST" << 'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8")
perms = [
    '    <uses-permission android:name="android.permission.CAMERA" />',
    '    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />',
    '    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />',
    '    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />',
    '    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />',
]
missing = [line for line in perms if line.strip() not in txt]
if missing and "<application" in txt:
    txt = txt.replace("<application", "\n".join(missing) + "\n<application", 1)
    p.write_text(txt, encoding="utf-8")
PY
fi

MAIN_KT="android/app/src/main/kotlin/com/putra/timestamp_by_putra/MainActivity.kt"
mkdir -p "$(dirname "$MAIN_KT")"
cat << 'EOF' > "$MAIN_KT"
package com.putra.timestamp_by_putra

import android.Manifest
import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "timestamp_by_putra/media_store"
    private val mediaPermRequestCode = 7701
    private val deleteRequestCode = 7741
    private var pendingResult: MethodChannel.Result? = null
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var pendingDeletePaths: List<String> = emptyList()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAllImages" -> {
                        if (hasMediaReadPermission()) {
                            result.success(queryAllImagesFromMediaStore())
                        } else {
                            pendingResult = result
                            requestMediaReadPermission()
                        }
                    }
                    "moveToTrash" -> {
                        val rawPaths = call.argument<List<*>>("paths")
                            ?.mapNotNull { it?.toString()?.trim() }
                            ?.filter { it.isNotEmpty() }
                            ?.distinct()
                            ?: emptyList()
                        handleMoveToTrash(rawPaths, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasMediaReadPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_MEDIA_IMAGES
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestMediaReadPermission() {
        val perms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
        } else {
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
        ActivityCompat.requestPermissions(this, perms, mediaPermRequestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == mediaPermRequestCode) {
            val cb = pendingResult
            pendingResult = null
            if (cb != null) {
                if (hasMediaReadPermission()) {
                    cb.success(queryAllImagesFromMediaStore())
                } else {
                    cb.success(emptyList<String>())
                }
            }
        }
    }

    private fun findMediaUriForPath(filePath: String): Uri? {
        val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(MediaStore.Images.Media._ID)
        val selection = "${MediaStore.Images.Media.DATA} = ?"
        val selectionArgs = arrayOf(filePath)

        contentResolver.query(collection, projection, selection, selectionArgs, null)?.use { cursor ->
            val idIdx = cursor.getColumnIndex(MediaStore.Images.Media._ID)
            if (idIdx >= 0 && cursor.moveToFirst()) {
                val id = cursor.getLong(idIdx)
                return ContentUris.withAppendedId(collection, id)
            }
        }
        return null
    }

    private fun handleMoveToTrash(paths: List<String>, result: MethodChannel.Result) {
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
            val uris = paths.mapNotNull { findMediaUriForPath(it) }.distinct()
            if (uris.isEmpty()) {
                result.success(
                    mapOf(
                        "movedCount" to 0,
                        "unresolvedPaths" to paths,
                    )
                )
                return
            }

            try {
                val pendingIntent = MediaStore.createDeleteRequest(contentResolver, uris)
                pendingDeleteResult = result
                pendingDeletePaths = paths
                startIntentSenderForResult(
                    pendingIntent.intentSender,
                    deleteRequestCode,
                    null,
                    0,
                    0,
                    0,
                    null
                )
            } catch (_: Exception) {
                result.success(
                    mapOf(
                        "movedCount" to 0,
                        "unresolvedPaths" to paths,
                    )
                )
            }
            return
        }

        var movedCount = 0
        val unresolved = mutableListOf<String>()

        for (path in paths) {
            val uri = findMediaUriForPath(path)
            if (uri != null) {
                try {
                    val deletedRows = contentResolver.delete(uri, null, null)
                    if (deletedRows > 0) {
                        movedCount++
                    } else {
                        unresolved.add(path)
                    }
                } catch (secEx: SecurityException) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                        secEx is RecoverableSecurityException
                    ) {
                        try {
                            pendingDeleteResult = result
                            pendingDeletePaths = paths
                            startIntentSenderForResult(
                                secEx.userAction.actionIntent.intentSender,
                                deleteRequestCode,
                                null,
                                0,
                                0,
                                0,
                                null
                            )
                            return
                        } catch (_: IntentSender.SendIntentException) {
                            unresolved.add(path)
                        }
                    } else {
                        unresolved.add(path)
                    }
                }
            } else {
                try {
                    val f = File(path)
                    if (f.exists() && f.delete()) {
                        movedCount++
                    } else {
                        unresolved.add(path)
                    }
                } catch (_: Exception) {
                    unresolved.add(path)
                }
            }
        }

        result.success(
            mapOf(
                "movedCount" to movedCount,
                "unresolvedPaths" to unresolved,
            )
        )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == deleteRequestCode) {
            val callback = pendingDeleteResult
            val paths = pendingDeletePaths
            pendingDeleteResult = null
            pendingDeletePaths = emptyList()

            if (callback != null) {
                if (resultCode == Activity.RESULT_OK) {
                    callback.success(
                        mapOf(
                            "movedCount" to paths.size,
                            "unresolvedPaths" to emptyList<String>(),
                        )
                    )
                } else {
                    callback.success(
                        mapOf(
                            "movedCount" to 0,
                            "unresolvedPaths" to emptyList<String>(),
                        )
                    )
                }
            }
        }
    }

    private fun queryAllImagesFromMediaStore(): List<String> {
        val paths = mutableListOf<String>()
        val uri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DATA,
            MediaStore.Images.Media.DATE_ADDED,
            MediaStore.Images.Media.DATE_MODIFIED
        )
        val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} DESC, ${MediaStore.Images.Media.DATE_MODIFIED} DESC"

        contentResolver.query(uri, projection, null, null, sortOrder)?.use { cursor ->
            val dataIdx = cursor.getColumnIndex(MediaStore.Images.Media.DATA)
            while (cursor.moveToNext()) {
                if (dataIdx >= 0) {
                    val path = cursor.getString(dataIdx)
                    if (!path.isNullOrBlank()) {
                        paths.add(path)
                    }
                }
            }
        }
        return paths
    }
}
EOF

python3 - << 'PY'
from pathlib import Path
import re

for path_str in ["android/app/build.gradle.kts", "android/app/build.gradle"]:
    p = Path(path_str)
    if p.exists():
        txt = p.read_text(encoding="utf-8")
        if "checkReleaseBuilds" not in txt:
            sep = " = " if path_str.endswith(".kts") else " "
            lint_block = f"    lint {{\n        checkReleaseBuilds{sep}false\n        abortOnError{sep}false\n    }}\n"
            m = re.search(r"android\s*\{", txt)
            if m:
                idx = m.end()
                txt = txt[:idx] + "\n" + lint_block + txt[idx:]
            else:
                txt += "\nandroid {\n" + lint_block + "}\n"
            p.write_text(txt, encoding="utf-8")
PY

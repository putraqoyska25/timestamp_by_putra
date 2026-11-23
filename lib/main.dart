import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Error kamera awal: $e');
  }
  runApp(const TimestampByPutraApp());
}

class TimestampByPutraApp extends StatelessWidget {
  const TimestampByPutraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Timestamp by Putra',
      theme: ThemeData.dark(useMaterial3: true),
      home: const CameraScreen(),
    );
  }
}

enum ActiveDrawer { none, watermarkEdit }

enum StampFormSize { small, medium, large }

enum StampTextColor { white, black, red, yellow, green, blue }

enum PhotoAspectRatio { ratio1x1, ratio4x3, ratio16x9 }

enum ImageQualityPreset { p1080, p720, p480, p360 }

enum CollageLayoutId {
  twoRows,
  twoCols,
  threeTopOneBottomTwo,
  threeRows,
  fourGrid2x2,
  fourRows121,
  fiveRows212,
  sixGrid2x3,
  sixHeroLeft2Right3Bottom,
  sixHeroLeft3Right2Bottom,
}

class _CollageLayoutDef {
  final CollageLayoutId id;
  final int photoCount;
  final String label;
  final double aspectRatio;

  const _CollageLayoutDef({
    required this.id,
    required this.photoCount,
    required this.label,
    required this.aspectRatio,
  });
}

class _CollageSlotRect {
  final int index;
  final double x;
  final double y;
  final double w;
  final double h;

  const _CollageSlotRect({
    required this.index,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });
}

class _CollageLayoutCatalog {
  static const List<_CollageLayoutDef> all = [
    _CollageLayoutDef(
      id: CollageLayoutId.twoRows,
      photoCount: 2,
      label: '2 Baris',
      aspectRatio: 3.0 / 4.0,
    ),
    _CollageLayoutDef(
      id: CollageLayoutId.twoCols,
      photoCount: 2,
      label: '2 Kolom',
      aspectRatio: 4.0 / 3.0,
    ),
    _CollageLayoutDef(
      id: CollageLayoutId.threeTopOneBottomTwo,
      photoCount: 3,
      label: '1 Atas + 2 Bawah',
      aspectRatio: 3.0 / 4.0,
    ),
    _CollageLayoutDef(
      id: CollageLayoutId.threeRows,
      photoCount: 3,
      label: '3 Baris',
      aspectRatio: 3.0 / 4.0,
    ),
    _CollageLayoutDef(
      id: CollageLayoutId.fourGrid2x2,
      photoCount: 4,
      label: 'Grid 2x2',
      aspectRatio: 1.0,
    ),
    _CollageLayoutDef(
      id: CollageLayoutId.fourRows121,
      photoCount: 4,
      label: '1 Atas + 2 Tengah + 1 Bawah',
      aspectRatio: 3.0 / 4.0,
    ),
    _CollageLayoutDef(
      id: CollageLayoutId.fiveRows212,
      photoCount: 5,
      label: '2 Atas + 1 Tengah + 2 Bawah',
      aspectRatio: 3.0 / 4.0,
    ),
    _CollageLayoutDef(
      id: CollageLayoutId.sixGrid2x3,
      photoCount: 6,
      label: 'Grid 2x3',
      aspectRatio: 3.0 / 4.0,
    ),
    _CollageLayoutDef(
      id: CollageLayoutId.sixHeroLeft2Right3Bottom,
      photoCount: 6,
      label: '1 Besar Kiri + 2 Kanan + 3 Bawah',
      aspectRatio: 3.0 / 4.0,
    ),
    _CollageLayoutDef(
      id: CollageLayoutId.sixHeroLeft3Right2Bottom,
      photoCount: 6,
      label: '1 Besar Kiri + 3 Kanan + 2 Bawah',
      aspectRatio: 3.0 / 4.0,
    ),
  ];

  static List<_CollageLayoutDef> layoutsForCount(int count) {
    return all.where((d) => d.photoCount == count).toList();
  }

  static _CollageLayoutDef defaultForCount(int count) {
    final list = layoutsForCount(count);
    return list.isNotEmpty ? list.first : all.first;
  }

  static _CollageLayoutDef findById(CollageLayoutId id) {
    for (final d in all) {
      if (d.id == id) return d;
    }
    return all.first;
  }

  static List<_CollageSlotRect> computeSlots({
    required CollageLayoutId layoutId,
    required double canvasW,
    required double canvasH,
    required double gap,
    required double outerPadding,
  }) {
    final double innerW = max(10.0, canvasW - (outerPadding * 2.0));
    final double innerH = max(10.0, canvasH - (outerPadding * 2.0));
    final double left = outerPadding;
    final double top = outerPadding;

    switch (layoutId) {
      case CollageLayoutId.twoRows:
        final double rowH = max(4.0, (innerH - gap) / 2.0);
        return [
          _CollageSlotRect(index: 0, x: left, y: top, w: innerW, h: rowH),
          _CollageSlotRect(
            index: 1,
            x: left,
            y: top + rowH + gap,
            w: innerW,
            h: rowH,
          ),
        ];

      case CollageLayoutId.twoCols:
        final double colW = max(4.0, (innerW - gap) / 2.0);
        return [
          _CollageSlotRect(index: 0, x: left, y: top, w: colW, h: innerH),
          _CollageSlotRect(
            index: 1,
            x: left + colW + gap,
            y: top,
            w: colW,
            h: innerH,
          ),
        ];

      case CollageLayoutId.threeTopOneBottomTwo:
        final double topH = max(4.0, (innerH - gap) * 0.52);
        final double botH = max(4.0, innerH - gap - topH);
        final double botW = max(4.0, (innerW - gap) / 2.0);
        return [
          _CollageSlotRect(index: 0, x: left, y: top, w: innerW, h: topH),
          _CollageSlotRect(
            index: 1,
            x: left,
            y: top + topH + gap,
            w: botW,
            h: botH,
          ),
          _CollageSlotRect(
            index: 2,
            x: left + botW + gap,
            y: top + topH + gap,
            w: botW,
            h: botH,
          ),
        ];

      case CollageLayoutId.threeRows:
        final double rowH = max(4.0, (innerH - (gap * 2.0)) / 3.0);
        return [
          _CollageSlotRect(index: 0, x: left, y: top, w: innerW, h: rowH),
          _CollageSlotRect(
            index: 1,
            x: left,
            y: top + rowH + gap,
            w: innerW,
            h: rowH,
          ),
          _CollageSlotRect(
            index: 2,
            x: left,
            y: top + ((rowH + gap) * 2.0),
            w: innerW,
            h: rowH,
          ),
        ];

      case CollageLayoutId.fourGrid2x2:
        final double colW = max(4.0, (innerW - gap) / 2.0);
        final double rowH = max(4.0, (innerH - gap) / 2.0);
        return [
          _CollageSlotRect(index: 0, x: left, y: top, w: colW, h: rowH),
          _CollageSlotRect(
            index: 1,
            x: left + colW + gap,
            y: top,
            w: colW,
            h: rowH,
          ),
          _CollageSlotRect(
            index: 2,
            x: left,
            y: top + rowH + gap,
            w: colW,
            h: rowH,
          ),
          _CollageSlotRect(
            index: 3,
            x: left + colW + gap,
            y: top + rowH + gap,
            w: colW,
            h: rowH,
          ),
        ];

      case CollageLayoutId.fourRows121:
        final double topH = max(4.0, (innerH - (gap * 2.0)) * 0.28);
        final double midH = max(4.0, (innerH - (gap * 2.0)) * 0.44);
        final double botH = max(4.0, innerH - (gap * 2.0) - topH - midH);
        final double midW = max(4.0, (innerW - gap) / 2.0);
        return [
          _CollageSlotRect(index: 0, x: left, y: top, w: innerW, h: topH),
          _CollageSlotRect(
            index: 1,
            x: left,
            y: top + topH + gap,
            w: midW,
            h: midH,
          ),
          _CollageSlotRect(
            index: 2,
            x: left + midW + gap,
            y: top + topH + gap,
            w: midW,
            h: midH,
          ),
          _CollageSlotRect(
            index: 3,
            x: left,
            y: top + topH + gap + midH + gap,
            w: innerW,
            h: botH,
          ),
        ];

      case CollageLayoutId.fiveRows212:
        final double topH = max(4.0, (innerH - (gap * 2.0)) * 0.34);
        final double midH = max(4.0, (innerH - (gap * 2.0)) * 0.32);
        final double botH = max(4.0, innerH - (gap * 2.0) - topH - midH);
        final double topW = max(4.0, (innerW - gap) / 2.0);
        final double botW = max(4.0, (innerW - gap) / 2.0);
        return [
          _CollageSlotRect(index: 0, x: left, y: top, w: topW, h: topH),
          _CollageSlotRect(
            index: 1,
            x: left + topW + gap,
            y: top,
            w: topW,
            h: topH,
          ),
          _CollageSlotRect(
            index: 2,
            x: left,
            y: top + topH + gap,
            w: innerW,
            h: midH,
          ),
          _CollageSlotRect(
            index: 3,
            x: left,
            y: top + topH + gap + midH + gap,
            w: botW,
            h: botH,
          ),
          _CollageSlotRect(
            index: 4,
            x: left + botW + gap,
            y: top + topH + gap + midH + gap,
            w: botW,
            h: botH,
          ),
        ];

      case CollageLayoutId.sixGrid2x3:
        final double colW = max(4.0, (innerW - gap) / 2.0);
        final double rowH = max(4.0, (innerH - (gap * 2.0)) / 3.0);
        return [
          for (int r = 0; r < 3; r++)
            for (int c = 0; c < 2; c++)
              _CollageSlotRect(
                index: (r * 2) + c,
                x: left + (c * (colW + gap)),
                y: top + (r * (rowH + gap)),
                w: colW,
                h: rowH,
              ),
        ];

      case CollageLayoutId.sixHeroLeft2Right3Bottom:
        final double upperH = max(4.0, (innerH - gap) * 0.66);
        final double botH = max(4.0, innerH - gap - upperH);
        final double leftHeroW = max(4.0, (innerW - gap) * 0.56);
        final double rightColW = max(4.0, innerW - gap - leftHeroW);
        final double rightItemH = max(4.0, (upperH - gap) / 2.0);
        final double botItemW = max(4.0, (innerW - (gap * 2.0)) / 3.0);
        return [
          _CollageSlotRect(
            index: 0,
            x: left,
            y: top,
            w: leftHeroW,
            h: upperH,
          ),
          _CollageSlotRect(
            index: 1,
            x: left + leftHeroW + gap,
            y: top,
            w: rightColW,
            h: rightItemH,
          ),
          _CollageSlotRect(
            index: 2,
            x: left + leftHeroW + gap,
            y: top + rightItemH + gap,
            w: rightColW,
            h: rightItemH,
          ),
          for (int b = 0; b < 3; b++)
            _CollageSlotRect(
              index: 3 + b,
              x: left + (b * (botItemW + gap)),
              y: top + upperH + gap,
              w: botItemW,
              h: botH,
            ),
        ];

      case CollageLayoutId.sixHeroLeft3Right2Bottom:
        final double upperH = max(4.0, (innerH - gap) * 0.68);
        final double botH = max(4.0, innerH - gap - upperH);
        final double leftHeroW = max(4.0, (innerW - gap) * 0.54);
        final double rightColW = max(4.0, innerW - gap - leftHeroW);
        final double rightItemH = max(4.0, (upperH - (gap * 2.0)) / 3.0);
        final double botItemW = max(4.0, (innerW - gap) / 2.0);
        return [
          _CollageSlotRect(
            index: 0,
            x: left,
            y: top,
            w: leftHeroW,
            h: upperH,
          ),
          for (int r = 0; r < 3; r++)
            _CollageSlotRect(
              index: 1 + r,
              x: left + leftHeroW + gap,
              y: top + (r * (rightItemH + gap)),
              w: rightColW,
              h: rightItemH,
            ),
          _CollageSlotRect(
            index: 4,
            x: left,
            y: top + upperH + gap,
            w: botItemW,
            h: botH,
          ),
          _CollageSlotRect(
            index: 5,
            x: left + botItemW + gap,
            y: top + upperH + gap,
            w: botItemW,
            h: botH,
          ),
        ];
    }
  }
}

class _NativeBrightnessService {
  static const MethodChannel _channel =
      MethodChannel('timestamp_by_putra/screen_brightness');
  static bool _isBoosted = false;

  static Future<void> boostToMax() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setMaxBrightness');
      _isBoosted = true;
    } catch (e) {
      debugPrint('Gagal menaikkan kecerahan layar native: $e');
    }
  }

  static Future<void> restoreNormal() async {
    if (!Platform.isAndroid) return;
    if (!_isBoosted) return;
    try {
      await _channel.invokeMethod('restoreBrightness');
    } catch (e) {
      debugPrint('Gagal memulihkan kecerahan layar native: $e');
    } finally {
      _isBoosted = false;
    }
  }
}

class _WatermarkConfig {
  final bool showLogo;
  final String? logoFilePath;
  final bool showTime;
  final bool isManualTime;
  final DateTime manualDateTime;
  final bool showAddress;
  final String customAddress;
  final bool showCoords;
  final String gpsCoordsText;
  final bool showCompany;
  final String companyText;
  final bool showPersonName;
  final String personNameText;
  final StampFormSize formSize;
  final StampTextColor textColor;

  const _WatermarkConfig({
    required this.showLogo,
    required this.logoFilePath,
    required this.showTime,
    required this.isManualTime,
    required this.manualDateTime,
    required this.showAddress,
    required this.customAddress,
    required this.showCoords,
    required this.gpsCoordsText,
    required this.showCompany,
    required this.companyText,
    required this.showPersonName,
    required this.personNameText,
    required this.formSize,
    this.textColor = StampTextColor.white,
  });

  _WatermarkConfig copyWith({
    bool? showLogo,
    String? logoFilePath,
    bool clearLogo = false,
    bool? showTime,
    bool? isManualTime,
    DateTime? manualDateTime,
    bool? showAddress,
    String? customAddress,
    bool? showCoords,
    String? gpsCoordsText,
    bool? showCompany,
    String? companyText,
    bool? showPersonName,
    String? personNameText,
    StampFormSize? formSize,
    StampTextColor? textColor,
  }) {
    return _WatermarkConfig(
      showLogo: showLogo ?? this.showLogo,
      logoFilePath: clearLogo ? null : (logoFilePath ?? this.logoFilePath),
      showTime: showTime ?? this.showTime,
      isManualTime: isManualTime ?? this.isManualTime,
      manualDateTime: manualDateTime ?? this.manualDateTime,
      showAddress: showAddress ?? this.showAddress,
      customAddress: customAddress ?? this.customAddress,
      showCoords: showCoords ?? this.showCoords,
      gpsCoordsText: gpsCoordsText ?? this.gpsCoordsText,
      showCompany: showCompany ?? this.showCompany,
      companyText: companyText ?? this.companyText,
      showPersonName: showPersonName ?? this.showPersonName,
      personNameText: personNameText ?? this.personNameText,
      formSize: formSize ?? this.formSize,
      textColor: textColor ?? this.textColor,
    );
  }
}

class _PersistentAppSettings {
  final bool showLogo;
  final String? logoFilePath;
  final bool showTime;
  final bool showAddress;
  final String customAddress;
  final bool showCoords;
  final bool showCompany;
  final String companyText;
  final bool showPersonName;
  final String personNameText;
  final StampFormSize formSize;
  final StampTextColor textColor;
  final PhotoAspectRatio aspectRatio;
  final ImageQualityPreset qualityPreset;
  final bool shutterSoundEnabled;
  final bool gridEnabled;

  const _PersistentAppSettings({
    this.showLogo = false,
    this.logoFilePath,
    this.showTime = true,
    this.showAddress = true,
    this.customAddress =
        'BPPP Ambon, Jl. Dr. J. Leimena, Rumah Tiga, Kec. Tlk. Ambon, Kota Ambon, Maluku',
    this.showCoords = false,
    this.showCompany = false,
    this.companyText = '',
    this.showPersonName = false,
    this.personNameText = '',
    this.formSize = StampFormSize.medium,
    this.textColor = StampTextColor.white,
    this.aspectRatio = PhotoAspectRatio.ratio4x3,
    this.qualityPreset = ImageQualityPreset.p720,
    this.shutterSoundEnabled = true,
    this.gridEnabled = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'showLogo': showLogo,
      'logoFilePath': logoFilePath,
      'showTime': showTime,
      'showAddress': showAddress,
      'customAddress': customAddress,
      'showCoords': showCoords,
      'showCompany': showCompany,
      'companyText': companyText,
      'showPersonName': showPersonName,
      'personNameText': personNameText,
      'formSize': formSize.name,
      'textColor': textColor.name,
      'aspectRatio': aspectRatio.name,
      'qualityPreset': qualityPreset.name,
      'shutterSoundEnabled': shutterSoundEnabled,
      'gridEnabled': gridEnabled,
    };
  }

  factory _PersistentAppSettings.fromJson(Map<String, dynamic> map) {
    T parseEnum<T extends Enum>(List<T> values, dynamic raw, T fallback) {
      if (raw is String) {
        for (final v in values) {
          if (v.name == raw) return v;
        }
      }
      return fallback;
    }

    return _PersistentAppSettings(
      showLogo: map['showLogo'] is bool ? map['showLogo'] as bool : false,
      logoFilePath: map['logoFilePath'] is String
          ? (map['logoFilePath'] as String).trim()
          : null,
      showTime: map['showTime'] is bool ? map['showTime'] as bool : true,
      showAddress:
          map['showAddress'] is bool ? map['showAddress'] as bool : true,
      customAddress: map['customAddress'] is String
          ? map['customAddress'] as String
          : 'BPPP Ambon, Jl. Dr. J. Leimena, Rumah Tiga, Kec. Tlk. Ambon, Kota Ambon, Maluku',
      showCoords: map['showCoords'] is bool ? map['showCoords'] as bool : false,
      showCompany:
          map['showCompany'] is bool ? map['showCompany'] as bool : false,
      companyText:
          map['companyText'] is String ? map['companyText'] as String : '',
      showPersonName:
          map['showPersonName'] is bool ? map['showPersonName'] as bool : false,
      personNameText: map['personNameText'] is String
          ? map['personNameText'] as String
          : '',
      formSize: parseEnum(
        StampFormSize.values,
        map['formSize'],
        StampFormSize.medium,
      ),
      textColor: parseEnum(
        StampTextColor.values,
        map['textColor'],
        StampTextColor.white,
      ),
      aspectRatio: parseEnum(
        PhotoAspectRatio.values,
        map['aspectRatio'],
        PhotoAspectRatio.ratio4x3,
      ),
      qualityPreset: parseEnum(
        ImageQualityPreset.values,
        map['qualityPreset'],
        ImageQualityPreset.p720,
      ),
      shutterSoundEnabled: map['shutterSoundEnabled'] is bool
          ? map['shutterSoundEnabled'] as bool
          : true,
      gridEnabled:
          map['gridEnabled'] is bool ? map['gridEnabled'] as bool : false,
    );
  }
}

class _AppPrefsStore {
  static _PersistentAppSettings _current = const _PersistentAppSettings();
  static Future<void> _writeChain = Future<void>.value();

  static _PersistentAppSettings get current => _current;

  static Future<File> _prefsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}app_prefs_v1.json');
  }

  static Future<String> persistLogoFile(String sourcePath) async {
    final src = File(sourcePath);
    if (!await src.exists()) {
      return sourcePath;
    }
    final dir = await getApplicationDocumentsDirectory();
    String ext = 'png';
    final dotIdx = sourcePath.lastIndexOf('.');
    if (dotIdx != -1 && dotIdx < sourcePath.length - 1) {
      final candidate = sourcePath.substring(dotIdx + 1).toLowerCase();
      if (candidate.length <= 5 && RegExp(r'^[a-z0-9]+$').hasMatch(candidate)) {
        ext = candidate;
      }
    }
    final destPath =
        '${dir.path}${Platform.pathSeparator}watermark_logo_saved.$ext';
    if (src.path != destPath) {
      await src.copy(destPath);
    }
    return destPath;
  }

  static Future<_PersistentAppSettings> load() async {
    try {
      final file = await _prefsFile();
      if (!await file.exists()) {
        return _current;
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return _current;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        var loaded = _PersistentAppSettings.fromJson(decoded);
        final lp = loaded.logoFilePath;
        if (lp != null && lp.isNotEmpty && !await File(lp).exists()) {
          loaded = _PersistentAppSettings(
            showLogo: false,
            logoFilePath: null,
            showTime: loaded.showTime,
            showAddress: loaded.showAddress,
            customAddress: loaded.customAddress,
            showCoords: loaded.showCoords,
            showCompany: loaded.showCompany,
            companyText: loaded.companyText,
            showPersonName: loaded.showPersonName,
            personNameText: loaded.personNameText,
            formSize: loaded.formSize,
            textColor: loaded.textColor,
            aspectRatio: loaded.aspectRatio,
            qualityPreset: loaded.qualityPreset,
            shutterSoundEnabled: loaded.shutterSoundEnabled,
            gridEnabled: loaded.gridEnabled,
          );
        }
        _current = loaded;
      }
    } catch (e) {
      debugPrint('Gagal membaca app_prefs: $e');
    }
    return _current;
  }

  static Future<void> save(_PersistentAppSettings next) {
    _current = next;
    _writeChain = _writeChain.then((_) async {
      try {
        final file = await _prefsFile();
        final tmpFile = File('${file.path}.tmp');
        await tmpFile.writeAsString(jsonEncode(next.toJson()), flush: true);
        if (await file.exists()) {
          await file.delete();
        }
        await tmpFile.rename(file.path);
      } catch (e) {
        debugPrint('Gagal menyimpan app_prefs: $e');
      }
    });
    return _writeChain;
  }

  static Future<void> updateFromWatermarkConfig(_WatermarkConfig cfg) {
    return save(
      _PersistentAppSettings(
        showLogo: cfg.showLogo,
        logoFilePath: cfg.logoFilePath,
        showTime: cfg.showTime,
        showAddress: cfg.showAddress,
        customAddress: cfg.customAddress,
        showCoords: cfg.showCoords,
        showCompany: cfg.showCompany,
        companyText: cfg.companyText,
        showPersonName: cfg.showPersonName,
        personNameText: cfg.personNameText,
        formSize: cfg.formSize,
        textColor: cfg.textColor,
        aspectRatio: _current.aspectRatio,
        qualityPreset: _current.qualityPreset,
        shutterSoundEnabled: _current.shutterSoundEnabled,
        gridEnabled: _current.gridEnabled,
      ),
    );
  }
}

class _ShutterAudioService {
  static AudioPlayer? _player;
  static String? _cachedWavFilePath;

  static Uint8List _buildLoudMechanicalShutterWavBytes() {
    const int sampleRate = 44100;
    // 180ms bunyi aktif + 240ms ekor hening agar Android Audio HAL tidak memotong klik
    const int activeSamples = 7938;
    const int tailSilenceSamples = 10584;
    const int totalSamples = activeSamples + tailSilenceSamples;

    final List<double> samples = List<double>.filled(totalSamples, 0.0);
    final Random rng = Random(42);

    // 1. Klik pertama (cermin/tirai buka) 0..3200 sampel (~72ms) - keras & tajam
    for (int i = 0; i < 3200 && i < activeSamples; i++) {
      final double t = i / sampleRate;
      final double env = exp(-i / 520.0);
      final double f1 = sin(2 * pi * 1150.0 * t) * 0.65;
      final double f2 = sin(2 * pi * 2350.0 * t) * 0.55;
      final double f3 = sin(2 * pi * 3400.0 * t) * 0.35;
      final double snap = (rng.nextDouble() * 2.0 - 1.0) * 0.85 * exp(-i / 180.0);
      samples[i] += (f1 + f2 + f3 + snap) * env * 1.45;
    }

    // 2. Klik kedua (tirai tutup) 3600..7800 sampel (~81ms..176ms) - resonansi penuh
    for (int i = 3600; i < 7800 && i < activeSamples; i++) {
      final int local = i - 3600;
      final double t = local / sampleRate;
      final double env = exp(-local / 620.0);
      final double f1 = sin(2 * pi * 980.0 * t) * 0.70;
      final double f2 = sin(2 * pi * 1880.0 * t) * 0.55;
      final double snap =
          (rng.nextDouble() * 2.0 - 1.0) * 0.75 * exp(-local / 210.0);
      samples[i] += (f1 + f2 + snap) * env * 1.40;
    }

    final int dataSize = totalSamples * 2;
    final ByteData buffer = ByteData(44 + dataSize);

    void writeAscii(int offset, String text) {
      for (int i = 0; i < text.length; i++) {
        buffer.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    buffer.setUint32(4, 36 + dataSize, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    buffer.setUint32(16, 16, Endian.little);
    buffer.setUint16(20, 1, Endian.little);
    buffer.setUint16(22, 1, Endian.little);
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little);
    buffer.setUint16(32, 2, Endian.little);
    buffer.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    buffer.setUint32(40, dataSize, Endian.little);

    int offset = 44;
    for (int i = 0; i < totalSamples; i++) {
      final double clamped = samples[i].clamp(-0.99, 0.99);
      final int pcm16 = (clamped * 32767.0).round();
      buffer.setInt16(offset, pcm16, Endian.little);
      offset += 2;
    }

    return buffer.buffer.asUint8List();
  }

  static Future<String> _ensureWavFile() async {
    final existingPath = _cachedWavFilePath;
    if (existingPath != null && await File(existingPath).exists()) {
      return existingPath;
    }
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}shutter_loud_v2.wav',
    );
    if (!await file.exists() || await file.length() == 0) {
      final wavBytes = _buildLoudMechanicalShutterWavBytes();
      await file.writeAsBytes(wavBytes, flush: true);
    }
    _cachedWavFilePath = file.path;
    return file.path;
  }

  static Future<AudioPlayer> _ensurePlayer() async {
    final existing = _player;
    if (existing != null) return existing;

    final player = AudioPlayer();
    await player.setPlayerMode(PlayerMode.mediaPlayer);
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setVolume(1.0);
    await player.setAudioContext(
      AudioContext(
        android: AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceSonification,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      ),
    );
    _player = player;
    return player;
  }

  static Future<void> warmupAudio() async {
    try {
      final path = await _ensureWavFile();
      final player = await _ensurePlayer();
      await player.setSource(DeviceFileSource(path));
    } catch (e) {
      debugPrint('Audio warmup info: $e');
    }
  }

  static Future<void> playShutterSound() async {
    try {
      final path = await _ensureWavFile();
      final player = await _ensurePlayer();
      await player.setVolume(1.0);
      await player.seek(Duration.zero);
      await player.play(DeviceFileSource(path), volume: 1.0);
      return;
    } catch (e) {
      debugPrint('DeviceFileSource shutter fallback: $e');
    }

    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }

  static Future<void> dispose() async {
    final p = _player;
    _player = null;
    if (p != null) {
      try {
        await p.dispose();
      } catch (_) {}
    }
  }
}

class _TrashService {
  static const MethodChannel _mediaStoreChannel =
      MethodChannel('timestamp_by_putra/media_store');

  static Future<bool> confirmMoveToTrash(
    BuildContext context, {
    required int count,
  }) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D24),
        title: const Text('Pindahkan ke Sampah'),
        content: Text(
          count == 1
              ? 'Foto ini akan dipindahkan ke sampah dan tidak dihapus secara permanen. Lanjutkan?'
              : '$count foto terpilih akan dipindahkan ke sampah dan tidak dihapus secara permanen. Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD9383A),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Pindah ke Sampah'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  static Future<int> moveFilesToTrash(List<String> filePaths) async {
    final List<String> cleanPaths = filePaths
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (cleanPaths.isEmpty) return 0;

    int movedCount = 0;
    List<String> remainingPaths = List<String>.from(cleanPaths);
    bool handledBySystemTrash = false;

    if (Platform.isAndroid) {
      try {
        final dynamic nativeRes = await _mediaStoreChannel.invokeMethod(
          'moveToTrash',
          {'paths': remainingPaths},
        );
        if (nativeRes is Map) {
          handledBySystemTrash = true;
          movedCount += (nativeRes['movedCount'] as num?)?.toInt() ?? 0;
          final List<dynamic>? unresolvedRaw =
              nativeRes['unresolvedPaths'] as List<dynamic>?;
          remainingPaths = unresolvedRaw != null
              ? unresolvedRaw
                  .map((e) => e?.toString().trim() ?? '')
                  .where((e) => e.isNotEmpty)
                  .toList()
              : const [];
        } else if (nativeRes is bool && nativeRes) {
          handledBySystemTrash = true;
          movedCount += remainingPaths.length;
          remainingPaths = const [];
        }
      } catch (e) {
        debugPrint('MediaStore moveToTrash belum tersedia/gagal: $e');
      }
    }

    if (!handledBySystemTrash && remainingPaths.isNotEmpty) {
      Directory? baseDir;
      try {
        baseDir = await getExternalStorageDirectory();
      } catch (_) {}
      baseDir ??= await getApplicationDocumentsDirectory();

      final Directory trashDir =
          Directory('${baseDir.path}${Platform.pathSeparator}Sampah');
      if (!await trashDir.exists()) {
        await trashDir.create(recursive: true);
      }

      for (final String p in remainingPaths) {
        try {
          final File src = File(p);
          if (!await src.exists()) continue;
          final String baseName = p.split(Platform.pathSeparator).last;
          final String destPath =
              '${trashDir.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}_$baseName';
          try {
            await src.rename(destPath);
            movedCount++;
          } catch (_) {
            await src.copy(destPath);
            await src.delete();
            movedCount++;
          }
        } catch (e) {
          debugPrint('Gagal memindahkan $p ke folder sampah: $e');
        }
      }
    }

    return movedCount;
  }
}

class _CameraGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final Paint gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final double w = size.width;
    final double h = size.height;

    final double col1 = w / 3.0;
    final double col2 = (w * 2.0) / 3.0;
    final double row1 = h / 3.0;
    final double row2 = (h * 2.0) / 3.0;

    canvas.drawLine(Offset(col1, 0), Offset(col1, h), gridPaint);
    canvas.drawLine(Offset(col2, 0), Offset(col2, h), gridPaint);
    canvas.drawLine(Offset(0, row1), Offset(w, row1), gridPaint);
    canvas.drawLine(Offset(0, row2), Offset(w, row2), gridPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StampRenderer {
  static const List<String> _hariIndo = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];

  static const List<String> _bulanIndo = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  static const double baseLogoSize = 54.0;

  static Color resolveTextColor(StampTextColor color) {
    switch (color) {
      case StampTextColor.white:
        return Colors.white;
      case StampTextColor.black:
        return Colors.black;
      case StampTextColor.red:
        return const Color(0xFFFF2E2E);
      case StampTextColor.yellow:
        return const Color(0xFFFFD000);
      case StampTextColor.green:
        return const Color(0xFF22C55E);
      case StampTextColor.blue:
        return const Color(0xFF2563EB);
    }
  }

  static String colorLabel(StampTextColor color) {
    switch (color) {
      case StampTextColor.white:
        return 'Putih';
      case StampTextColor.black:
        return 'Hitam';
      case StampTextColor.red:
        return 'Merah';
      case StampTextColor.yellow:
        return 'Kuning';
      case StampTextColor.green:
        return 'Hijau';
      case StampTextColor.blue:
        return 'Biru';
    }
  }

  static List<Shadow> resolveShadows(StampTextColor color) {
    if (color == StampTextColor.black) {
      return const [
        Shadow(
          color: Color(0xF2FFFFFF),
          offset: Offset(0, 0),
          blurRadius: 6.0,
        ),
        Shadow(
          color: Color(0xD9FFFFFF),
          offset: Offset(0, 1.5),
          blurRadius: 3.0,
        ),
      ];
    }
    return const [
      Shadow(
        color: Colors.black87,
        offset: Offset(0, 1.5),
        blurRadius: 4.0,
      ),
    ];
  }

  static double sizeMultiplier(StampFormSize size) {
    switch (size) {
      case StampFormSize.small:
        return 0.85;
      case StampFormSize.medium:
        return 1.00;
      case StampFormSize.large:
        return 1.24;
    }
  }

  static double aspectScaleFactor(int width, int height) {
    if (width <= 0 || height <= 0) return 1.0;
    final double ratio = width / height;
    if (ratio >= 0.95) {
      return 0.94;
    } else if (ratio >= 0.70) {
      return 1.0;
    } else {
      return 0.90;
    }
  }

  static String formatJamMenit(DateTime dt) {
    final String hh = dt.hour.toString().padLeft(2, '0');
    final String mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  static String formatTanggalLengkap(DateTime dt) {
    final String dd = dt.day.toString().padLeft(2, '0');
    final String bulan = _bulanIndo[dt.month - 1];
    final int yyyy = dt.year;
    return '$dd $bulan $yyyy';
  }

  static String formatHari(DateTime dt) {
    return _hariIndo[dt.weekday - 1];
  }

  static List<String> buildExtraDetailLines(_WatermarkConfig cfg) {
    final List<String> lines = [];
    if (cfg.showAddress && cfg.customAddress.trim().isNotEmpty) {
      lines.add(cfg.customAddress.trim());
    }
    if (cfg.showCoords && cfg.gpsCoordsText.trim().isNotEmpty) {
      lines.add(cfg.gpsCoordsText.trim());
    }
    if (cfg.showCompany && cfg.companyText.trim().isNotEmpty) {
      lines.add(cfg.companyText.trim());
    }
    if (cfg.showPersonName && cfg.personNameText.trim().isNotEmpty) {
      lines.add(cfg.personNameText.trim());
    }
    return lines;
  }

  static Future<ui.Image> renderOverlayImage({
    required int targetW,
    required int targetH,
    required DateTime activeDt,
    required _WatermarkConfig cfg,
  }) async {
    final double w = targetW.toDouble();
    final double h = targetH.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

    final double refScale = w / 390.0;
    final double ratioFactor = aspectScaleFactor(targetW, targetH);
    final double mult = sizeMultiplier(cfg.formSize);
    final double s = refScale * mult * ratioFactor;
    final double padLeft = 14.0 * refScale;
    final double padRight = 14.0 * refScale;
    final double padBottom = 12.0 * refScale;
    final double maxTextWidth = max(60.0, w - padLeft - padRight);

    final Color fgColor = resolveTextColor(cfg.textColor);
    final List<Shadow> textShadows = resolveShadows(cfg.textColor);

    ui.Image? logoImg;
    if (cfg.showLogo &&
        cfg.logoFilePath != null &&
        cfg.logoFilePath!.isNotEmpty) {
      final logoFile = File(cfg.logoFilePath!);
      if (await logoFile.exists()) {
        final logoBytes = await logoFile.readAsBytes();
        final logoCodec = await ui.instantiateImageCodec(logoBytes);
        final logoFrame = await logoCodec.getNextFrame();
        logoImg = logoFrame.image;
      }
    }

    final double logoSize = logoImg != null ? (baseLogoSize * s) : 0.0;
    final double logoBottomGap = logoImg != null ? (7.0 * s) : 0.0;

    TextPainter? jamPainter;
    TextPainter? tanggalPainter;
    TextPainter? hariPainter;
    double timeRowHeight = 0.0;

    if (cfg.showTime) {
      final jp = TextPainter(
        text: TextSpan(
          text: formatJamMenit(activeDt),
          style: TextStyle(
            color: fgColor,
            fontSize: 34.0 * s,
            fontWeight: FontWeight.w700,
            height: 1.0,
            shadows: textShadows,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      )..layout();

      final double dividerWidth = 2.5 * s;
      final double rightColMaxWidth = max(
        90.0 * refScale,
        maxTextWidth - jp.width - dividerWidth - (20.0 * s),
      );

      final tp = TextPainter(
        text: TextSpan(
          text: formatTanggalLengkap(activeDt),
          style: TextStyle(
            color: fgColor,
            fontSize: 14.5 * s,
            fontWeight: FontWeight.w600,
            shadows: textShadows,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: rightColMaxWidth);

      final hp = TextPainter(
        text: TextSpan(
          text: formatHari(activeDt),
          style: TextStyle(
            color: fgColor,
            fontSize: 13.5 * s,
            fontWeight: FontWeight.w400,
            shadows: textShadows,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: rightColMaxWidth);

      jamPainter = jp;
      tanggalPainter = tp;
      hariPainter = hp;
      timeRowHeight = max(
        jp.height,
        tp.height + (2.0 * s) + hp.height,
      );
    }

    final double topBlockHeight =
        (logoImg != null ? logoSize + logoBottomGap : 0.0) + timeRowHeight;

    final List<String> extraLines = buildExtraDetailLines(cfg);
    final String detailsCombined = extraLines.join('\n');

    TextPainter? detailsPainter;
    if (detailsCombined.isNotEmpty) {
      detailsPainter = TextPainter(
        text: TextSpan(
          text: detailsCombined,
          style: TextStyle(
            color: fgColor,
            fontSize: 13.0 * s,
            fontWeight: FontWeight.w400,
            height: 1.25,
            shadows: textShadows,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 6,
        ellipsis: '...',
      )..layout(maxWidth: maxTextWidth);
    }

    final double gapBelowHeader =
        (topBlockHeight > 0 && detailsPainter != null) ? (7.0 * s) : 0.0;
    final double totalStampHeight =
        topBlockHeight + gapBelowHeader + (detailsPainter?.height ?? 0.0);
    final double stampTopY = h - padBottom - totalStampHeight;

    if (totalStampHeight > 0) {
      final double gradTop = max(0.0, stampTopY - (18.0 * refScale));
      final gradPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, gradTop),
          Offset(0, h),
          [
            Colors.black.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.36),
          ],
        );
      canvas.drawRect(Rect.fromLTWH(0, gradTop, w, h - gradTop), gradPaint);
    }

    double currentY = stampTopY;

    if (logoImg != null) {
      canvas.drawImageRect(
        logoImg,
        Rect.fromLTWH(0, 0, logoImg.width.toDouble(), logoImg.height.toDouble()),
        Rect.fromLTWH(padLeft, currentY, logoSize, logoSize),
        Paint(),
      );
      logoImg.dispose();
      currentY += logoSize + logoBottomGap;
    }

    if (cfg.showTime &&
        jamPainter != null &&
        tanggalPainter != null &&
        hariPainter != null) {
      final jp = jamPainter;
      final tp = tanggalPainter;
      final hp = hariPainter;

      double curX = padLeft;
      jp.paint(
        canvas,
        Offset(curX, currentY + ((timeRowHeight - jp.height) / 2)),
      );

      final double dividerX = curX + jp.width + (10.0 * s);
      final double dividerHeight = 34.0 * s;
      final double dividerTopY =
          currentY + ((timeRowHeight - dividerHeight) / 2);

      canvas.drawRect(
        Rect.fromLTWH(dividerX, dividerTopY, 2.5 * s, dividerHeight),
        Paint()..color = const Color(0xFFFFD000),
      );

      final double rightColX = dividerX + (10.0 * s);
      final double rightColHeight = tp.height + (2.0 * s) + hp.height;
      final double rightColTopY =
          currentY + ((timeRowHeight - rightColHeight) / 2);

      tp.paint(canvas, Offset(rightColX, rightColTopY));
      hp.paint(
        canvas,
        Offset(rightColX, rightColTopY + tp.height + (2.0 * s)),
      );
    }

    if (detailsPainter != null) {
      final double addressY = stampTopY + topBlockHeight + gapBelowHeader;
      detailsPainter.paint(canvas, Offset(padLeft, addressY));
    }

    return recorder.endRecording().toImage(targetW, targetH);
  }

  static Future<Uint8List> buildStampedJpgBytes({
    required Uint8List baseJpgBytes,
    required DateTime activeDt,
    required _WatermarkConfig cfg,
  }) async {
    final img.Image? decoded = img.decodeImage(baseJpgBytes);
    if (decoded == null || decoded.width <= 4 || decoded.height <= 4) {
      throw Exception('Gagal mendekode gambar');
    }

    final img.Image baseImg = img.bakeOrientation(decoded);

    final ui.Image overlayUi = await renderOverlayImage(
      targetW: baseImg.width,
      targetH: baseImg.height,
      activeDt: activeDt,
      cfg: cfg,
    );

    final byteData =
        await overlayUi.toByteData(format: ui.ImageByteFormat.rawRgba);
    overlayUi.dispose();

    if (byteData != null && byteData.lengthInBytes > 0) {
      final img.Image overlayImg = img.Image.fromBytes(
        width: baseImg.width,
        height: baseImg.height,
        bytes: byteData.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      img.compositeImage(baseImg, overlayImg);
    }

    return Uint8List.fromList(img.encodeJpg(baseImg, quality: 90));
  }
}

Widget _buildStampOverlayWidget({
  required DateTime activeDt,
  required _WatermarkConfig cfg,
  required double boxWidth,
  required double boxHeight,
}) {
  final double refScale = boxWidth > 0 ? (boxWidth / 390.0) : 1.0;
  final double ratioFactor =
      _StampRenderer.aspectScaleFactor(boxWidth.round(), boxHeight.round());
  final double mult = _StampRenderer.sizeMultiplier(cfg.formSize);
  final double s = refScale * mult * ratioFactor;

  final Color fgColor = _StampRenderer.resolveTextColor(cfg.textColor);
  final List<Shadow> previewShadows = _StampRenderer.resolveShadows(cfg.textColor);

  final List<String> extraLines = _StampRenderer.buildExtraDetailLines(cfg);
  final bool hasLogo = cfg.showLogo &&
      cfg.logoFilePath != null &&
      cfg.logoFilePath!.isNotEmpty &&
      File(cfg.logoFilePath!).existsSync();

  if (!cfg.showTime && !hasLogo && extraLines.isEmpty) {
    return const SizedBox.shrink();
  }

  return IgnorePointer(
    child: Container(
      padding: EdgeInsets.fromLTRB(
        14 * refScale,
        18 * refScale,
        14 * refScale,
        12 * refScale,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.36),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasLogo) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(7 * s),
              child: Image.file(
                File(cfg.logoFilePath!),
                width: _StampRenderer.baseLogoSize * s,
                height: _StampRenderer.baseLogoSize * s,
                fit: BoxFit.cover,
              ),
            ),
            SizedBox(height: 7 * s),
          ],
          if (cfg.showTime)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  _StampRenderer.formatJamMenit(activeDt),
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: fgColor,
                    fontSize: 34 * s,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                    shadows: previewShadows,
                  ),
                ),
                SizedBox(width: 10 * s),
                Container(
                  width: 2.5 * s,
                  height: 34 * s,
                  color: const Color(0xFFFFD000),
                ),
                SizedBox(width: 10 * s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _StampRenderer.formatTanggalLengkap(activeDt),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fgColor,
                          fontSize: 14.5 * s,
                          fontWeight: FontWeight.w600,
                          shadows: previewShadows,
                        ),
                      ),
                      SizedBox(height: 2 * s),
                      Text(
                        _StampRenderer.formatHari(activeDt),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fgColor,
                          fontSize: 13.5 * s,
                          shadows: previewShadows,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          if (extraLines.isNotEmpty) ...[
            SizedBox(height: 7 * s),
            Text(
              extraLines.join('\n'),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fgColor,
                fontSize: 13.0 * s,
                height: 1.25,
                shadows: previewShadows,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _CameraSettingsScreen extends StatefulWidget {
  final bool shutterSoundEnabled;
  final bool gridEnabled;
  final PhotoAspectRatio aspectRatio;
  final ImageQualityPreset qualityPreset;
  final ValueChanged<bool> onShutterSoundChanged;
  final ValueChanged<bool> onGridChanged;
  final ValueChanged<PhotoAspectRatio> onAspectRatioChanged;
  final ValueChanged<ImageQualityPreset> onQualityPresetChanged;

  const _CameraSettingsScreen({
    required this.shutterSoundEnabled,
    required this.gridEnabled,
    required this.aspectRatio,
    required this.qualityPreset,
    required this.onShutterSoundChanged,
    required this.onGridChanged,
    required this.onAspectRatioChanged,
    required this.onQualityPresetChanged,
  });

  @override
  State<_CameraSettingsScreen> createState() => _CameraSettingsScreenState();
}

class _CameraSettingsScreenState extends State<_CameraSettingsScreen> {
  late bool _shutterSound;
  late bool _gridOn;
  late PhotoAspectRatio _aspect;
  late ImageQualityPreset _quality;

  @override
  void initState() {
    super.initState();
    _shutterSound = widget.shutterSoundEnabled;
    _gridOn = widget.gridEnabled;
    _aspect = widget.aspectRatio;
    _quality = widget.qualityPreset;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Pengaturan',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'Pengaturan Umum',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white60,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF161920),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: const Icon(
                    Icons.volume_up_outlined,
                    color: Colors.white70,
                    size: 24,
                  ),
                  title: const Text(
                    'Suara rana',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  trailing: Switch(
                    value: _shutterSound,
                    activeThumbColor: Colors.black,
                    activeTrackColor: const Color(0xFFFFD000),
                    onChanged: (val) {
                      setState(() => _shutterSound = val);
                      widget.onShutterSoundChanged(val);
                    },
                  ),
                ),
                const Divider(height: 1, color: Colors.white12, indent: 56),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: const Icon(
                    Icons.grid_on_outlined,
                    color: Colors.white70,
                    size: 24,
                  ),
                  title: const Text(
                    'Kisi / Grid',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  trailing: Switch(
                    value: _gridOn,
                    activeThumbColor: Colors.black,
                    activeTrackColor: const Color(0xFFFFD000),
                    onChanged: (val) {
                      setState(() => _gridOn = val);
                      widget.onGridChanged(val);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'Kamera & Hasil Foto',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white60,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF161920),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Rasio Gambar',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _MiniChipButton(
                      label: '1:1',
                      selected: _aspect == PhotoAspectRatio.ratio1x1,
                      onTap: () {
                        setState(() => _aspect = PhotoAspectRatio.ratio1x1);
                        widget.onAspectRatioChanged(PhotoAspectRatio.ratio1x1);
                      },
                    ),
                    const SizedBox(width: 8),
                    _MiniChipButton(
                      label: '4:3',
                      selected: _aspect == PhotoAspectRatio.ratio4x3,
                      onTap: () {
                        setState(() => _aspect = PhotoAspectRatio.ratio4x3);
                        widget.onAspectRatioChanged(PhotoAspectRatio.ratio4x3);
                      },
                    ),
                    const SizedBox(width: 8),
                    _MiniChipButton(
                      label: '16:9',
                      selected: _aspect == PhotoAspectRatio.ratio16x9,
                      onTap: () {
                        setState(() => _aspect = PhotoAspectRatio.ratio16x9);
                        widget.onAspectRatioChanged(PhotoAspectRatio.ratio16x9);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Colors.white12),
                const SizedBox(height: 14),
                const Text(
                  'Kualitas Gambar',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _MiniChipButton(
                      label: '1080p',
                      selected: _quality == ImageQualityPreset.p1080,
                      onTap: () {
                        setState(() => _quality = ImageQualityPreset.p1080);
                        widget.onQualityPresetChanged(ImageQualityPreset.p1080);
                      },
                    ),
                    const SizedBox(width: 6),
                    _MiniChipButton(
                      label: '720p',
                      selected: _quality == ImageQualityPreset.p720,
                      onTap: () {
                        setState(() => _quality = ImageQualityPreset.p720);
                        widget.onQualityPresetChanged(ImageQualityPreset.p720);
                      },
                    ),
                    const SizedBox(width: 6),
                    _MiniChipButton(
                      label: '480p',
                      selected: _quality == ImageQualityPreset.p480,
                      onTap: () {
                        setState(() => _quality = ImageQualityPreset.p480);
                        widget.onQualityPresetChanged(ImageQualityPreset.p480);
                      },
                    ),
                    const SizedBox(width: 6),
                    _MiniChipButton(
                      label: '360p',
                      selected: _quality == ImageQualityPreset.p360,
                      onTap: () {
                        setState(() => _quality = ImageQualityPreset.p360);
                        widget.onQualityPresetChanged(ImageQualityPreset.p360);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  static const MethodChannel _mediaStoreChannel =
      MethodChannel('timestamp_by_putra/media_store');

  CameraController? _controller;
  final Random _random = Random();
  final ImagePicker _picker = ImagePicker();

  CameraLensDirection _currentLens = CameraLensDirection.back;
  bool _flashEnabled = false;
  bool _screenFlashActive = false;
  bool _shutterBlinkActive = false;
  Timer? _shutterBlinkTimer;
  String? _cameraErrorMessage;
  bool _isInitializingCamera = false;
  bool _startupPermissionsRequested = false;

  bool _shutterSoundEnabled = true;
  bool _gridEnabled = false;

  Offset? _focusUiOffset;
  double _minExposureOffset = -2.0;
  double _maxExposureOffset = 2.0;
  double _currentExposureOffset = 0.0;
  bool _showFocusRing = false;
  bool _isDraggingExposure = false;
  Timer? _focusRingTimer;

  PhotoAspectRatio _aspectRatio = PhotoAspectRatio.ratio4x3;
  ImageQualityPreset _qualityPreset = ImageQualityPreset.p720;

  int _timerSeconds = 0;
  int? _countdownRemaining;
  Timer? _countdownTimer;

  bool _isSaving = false;
  bool _isCoolingDown = false;
  Timer? _cooldownTimer;

  bool _showLogo = false;
  String? _logoFilePath;

  bool _showTime = true;
  bool _isManualTime = false;
  DateTime _manualDateTime = DateTime.now();
  DateTime _systemNow = DateTime.now();
  Timer? _clockTimer;

  bool _showAddress = true;
  String _customAddress =
      'BPPP Ambon, Jl. Dr. J. Leimena, Rumah Tiga, Kec. Tlk. Ambon, Kota Ambon, Maluku';

  bool _showCoords = false;
  String _gpsCoordsText = 'Mencari GPS...';

  bool _showCompany = false;
  String _companyText = '';

  bool _showPersonName = false;
  String _personNameText = '';

  StampFormSize _formSize = StampFormSize.medium;
  StampTextColor _textColor = StampTextColor.white;
  ActiveDrawer _openDrawer = ActiveDrawer.none;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrapStartupSequence());
    _startClockTimer();
  }

  void _applyLoadedPersistentSettings(_PersistentAppSettings saved) {
    if (!mounted) return;
    setState(() {
      _showLogo = saved.showLogo;
      _logoFilePath = saved.logoFilePath;
      _showTime = saved.showTime;
      _isManualTime = false;
      _systemNow = DateTime.now();
      _showAddress = saved.showAddress;
      _customAddress = saved.customAddress;
      _showCoords = saved.showCoords;
      _showCompany = saved.showCompany;
      _companyText = saved.companyText;
      _showPersonName = saved.showPersonName;
      _personNameText = saved.personNameText;
      _formSize = saved.formSize;
      _textColor = saved.textColor;
      _aspectRatio = saved.aspectRatio;
      _qualityPreset = saved.qualityPreset;
      _shutterSoundEnabled = saved.shutterSoundEnabled;
      _gridEnabled = saved.gridEnabled;
    });
  }

  Future<void> _persistCurrentSettings() async {
    await _AppPrefsStore.save(
      _PersistentAppSettings(
        showLogo: _showLogo,
        logoFilePath: _logoFilePath,
        showTime: _showTime,
        showAddress: _showAddress,
        customAddress: _customAddress,
        showCoords: _showCoords,
        showCompany: _showCompany,
        companyText: _companyText,
        showPersonName: _showPersonName,
        personNameText: _personNameText,
        formSize: _formSize,
        textColor: _textColor,
        aspectRatio: _aspectRatio,
        qualityPreset: _qualityPreset,
        shutterSoundEnabled: _shutterSoundEnabled,
        gridEnabled: _gridEnabled,
      ),
    );
  }

  Future<void> _bootstrapStartupSequence() async {
    final saved = await _AppPrefsStore.load();
    _applyLoadedPersistentSettings(saved);

    await _initCameraByDirection(CameraLensDirection.back, refreshList: true);
    if (!mounted || _startupPermissionsRequested) return;
    _startupPermissionsRequested = true;

    if (Platform.isAndroid) {
      try {
        await _mediaStoreChannel.invokeMethod('requestMediaPermissions');
      } catch (e) {
        debugPrint('requestMediaPermissions awal: $e');
      }
    }

    if (!mounted) return;
    await _getLocation(requestIfDenied: true);

    if (!mounted) return;
    await _ShutterAudioService.warmupAudio();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _cancelCountdown();
      _cooldownTimer?.cancel();
      _cooldownTimer = null;
      _shutterBlinkTimer?.cancel();
      _shutterBlinkTimer = null;
      _focusRingTimer?.cancel();
      _focusRingTimer = null;
      _screenFlashActive = false;
      _shutterBlinkActive = false;
      _showFocusRing = false;
      _isDraggingExposure = false;
      unawaited(_NativeBrightnessService.restoreNormal());
      unawaited(_forceTorchOff(controllerOverride: _controller));
      if (_isManualTime ||
          _openDrawer != ActiveDrawer.none ||
          _currentLens != CameraLensDirection.back ||
          _isCoolingDown) {
        setState(() {
          _isManualTime = false;
          _openDrawer = ActiveDrawer.none;
          _isCoolingDown = false;
          _systemNow = DateTime.now();
        });
      }
      _disposeControllerSafely();
    } else if (state == AppLifecycleState.resumed) {
      _screenFlashActive = false;
      unawaited(_NativeBrightnessService.restoreNormal());
      setState(() {
        _isManualTime = false;
        _systemNow = DateTime.now();
      });
      unawaited(
        _initCameraByDirection(CameraLensDirection.back, refreshList: true),
      );
    }
  }

  Future<void> _playShutterSoundIfEnabled() async {
    if (!_shutterSoundEnabled) return;
    await _ShutterAudioService.playShutterSound();
  }

  Future<void> _openSettingsPage() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CameraSettingsScreen(
          shutterSoundEnabled: _shutterSoundEnabled,
          gridEnabled: _gridEnabled,
          aspectRatio: _aspectRatio,
          qualityPreset: _qualityPreset,
          onShutterSoundChanged: (val) {
            if (!mounted) return;
            setState(() => _shutterSoundEnabled = val);
            unawaited(_persistCurrentSettings());
            if (val) {
              unawaited(_ShutterAudioService.playShutterSound());
            }
          },
          onGridChanged: (val) {
            if (!mounted) return;
            setState(() => _gridEnabled = val);
            unawaited(_persistCurrentSettings());
          },
          onAspectRatioChanged: (ratio) {
            if (!mounted) return;
            setState(() => _aspectRatio = ratio);
            unawaited(_persistCurrentSettings());
          },
          onQualityPresetChanged: (preset) {
            unawaited(_setQualityPreset(preset));
          },
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _shutterSoundEnabled = _AppPrefsStore.current.shutterSoundEnabled;
        _gridEnabled = _AppPrefsStore.current.gridEnabled;
        _aspectRatio = _AppPrefsStore.current.aspectRatio;
        _qualityPreset = _AppPrefsStore.current.qualityPreset;
      });
    }
  }

  Future<void> _disposeControllerSafely() async {
    final prev = _controller;
    _controller = null;
    if (prev != null) {
      try {
        await prev.setFlashMode(FlashMode.off);
      } catch (_) {}
      try {
        await prev.dispose();
      } catch (e) {
        debugPrint('Error dispose controller: $e');
      }
    }
  }

  void _startClockTimer() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!_isManualTime) {
        setState(() {
          _systemNow = DateTime.now();
        });
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (_countdownRemaining != null && mounted) {
      setState(() => _countdownRemaining = null);
    }
  }

  void _startPostCaptureCooldown({int milliseconds = 600}) {
    _cooldownTimer?.cancel();
    if (!mounted) return;
    setState(() => _isCoolingDown = true);
    _cooldownTimer = Timer(Duration(milliseconds: milliseconds), () {
      if (!mounted) return;
      setState(() => _isCoolingDown = false);
    });
  }

  void _triggerShutterBlink({int milliseconds = 110}) {
    _shutterBlinkTimer?.cancel();
    if (!mounted) return;
    setState(() => _shutterBlinkActive = true);
    _shutterBlinkTimer = Timer(Duration(milliseconds: milliseconds), () {
      if (!mounted) return;
      setState(() => _shutterBlinkActive = false);
    });
  }

  void _scheduleFocusRingHide({int milliseconds = 3500}) {
    _focusRingTimer?.cancel();
    if (_isDraggingExposure) return;
    _focusRingTimer = Timer(Duration(milliseconds: milliseconds), () {
      if (!mounted || _isDraggingExposure) return;
      setState(() => _showFocusRing = false);
    });
  }

  Future<void> _lockFocusAtPoint(
    Offset localPosition,
    BoxConstraints box,
  ) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (box.maxWidth <= 0 || box.maxHeight <= 0) return;

    final double nx = (localPosition.dx / box.maxWidth).clamp(0.0, 1.0);
    final double ny = (localPosition.dy / box.maxHeight).clamp(0.0, 1.0);
    final Offset norm = Offset(nx, ny);

    setState(() {
      _focusUiOffset = localPosition;
      _currentExposureOffset = 0.0;
      _showFocusRing = true;
    });
    _scheduleFocusRingHide(milliseconds: 3500);

    try {
      await ctrl.setExposureOffset(0.0);
    } catch (_) {}

    try {
      await ctrl.setFocusMode(FocusMode.auto);
    } catch (_) {}

    try {
      await ctrl.setFocusPoint(norm);
    } catch (e) {
      debugPrint('setFocusPoint tidak didukung pada lensa ini: $e');
    }

    try {
      await ctrl.setExposurePoint(norm);
    } catch (e) {
      debugPrint('setExposurePoint tidak didukung pada lensa ini: $e');
    }
  }

  Future<void> _setExposureValue(double value) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final double clamped = value.clamp(_minExposureOffset, _maxExposureOffset);
    setState(() {
      _currentExposureOffset = clamped;
      _showFocusRing = true;
    });
    try {
      await ctrl.setExposureOffset(clamped);
    } catch (e) {
      debugPrint('Gagal mengatur exposure offset: $e');
    }
  }

  void _handleVerticalExposureDragStart(
    DragStartDetails details,
    BoxConstraints box,
  ) {
    if (!_showFocusRing || _focusUiOffset == null) {
      unawaited(_lockFocusAtPoint(details.localPosition, box));
    }
    _focusRingTimer?.cancel();
    setState(() {
      _isDraggingExposure = true;
      _showFocusRing = true;
    });
  }

  void _handleVerticalExposureDragUpdate(
    DragUpdateDetails details,
    BoxConstraints box,
  ) {
    if (_maxExposureOffset <= _minExposureOffset) return;
    final double range = _maxExposureOffset - _minExposureOffset;
    final double dragSpan = max(140.0, box.maxHeight * 0.45);
    final double deltaOffset = (-details.delta.dy / dragSpan) * range;
    unawaited(_setExposureValue(_currentExposureOffset + deltaOffset));
  }

  void _handleVerticalExposureDragEnd() {
    if (!mounted) return;
    setState(() => _isDraggingExposure = false);
    _scheduleFocusRingHide(milliseconds: 3500);
  }

  int _normalizeTimer(int sec) {
    if (sec == 3 || sec == 5) return sec;
    return 0;
  }

  DateTime _getActiveDateTime() {
    return _isManualTime ? _manualDateTime : _systemNow;
  }

  _WatermarkConfig _currentWatermarkConfig() {
    return _WatermarkConfig(
      showLogo: _showLogo,
      logoFilePath: _logoFilePath,
      showTime: _showTime,
      isManualTime: _isManualTime,
      manualDateTime: _manualDateTime,
      showAddress: _showAddress,
      customAddress: _customAddress,
      showCoords: _showCoords,
      gpsCoordsText: _gpsCoordsText,
      showCompany: _showCompany,
      companyText: _companyText,
      showPersonName: _showPersonName,
      personNameText: _personNameText,
      formSize: _formSize,
      textColor: _textColor,
    );
  }

  void _applyWatermarkConfig(_WatermarkConfig cfg) {
    setState(() {
      _showLogo = cfg.showLogo;
      _logoFilePath = cfg.logoFilePath;
      _showTime = cfg.showTime;
      _isManualTime = cfg.isManualTime;
      _manualDateTime = cfg.manualDateTime;
      _showAddress = cfg.showAddress;
      _customAddress = cfg.customAddress;
      _showCoords = cfg.showCoords;
      _gpsCoordsText = cfg.gpsCoordsText;
      _showCompany = cfg.showCompany;
      _companyText = cfg.companyText;
      _showPersonName = cfg.showPersonName;
      _personNameText = cfg.personNameText;
      _formSize = cfg.formSize;
      _textColor = cfg.textColor;
    });
    unawaited(_persistCurrentSettings());
  }

  String _getFormSizeLabel() {
    switch (_formSize) {
      case StampFormSize.small:
        return 'Kecil';
      case StampFormSize.medium:
        return 'Sedang';
      case StampFormSize.large:
        return 'Besar';
    }
  }

  double _getAspectRatioValue() {
    switch (_aspectRatio) {
      case PhotoAspectRatio.ratio1x1:
        return 1.0;
      case PhotoAspectRatio.ratio4x3:
        return 3.0 / 4.0;
      case PhotoAspectRatio.ratio16x9:
        return 9.0 / 16.0;
    }
  }

  String _getAspectRatioLabel() {
    switch (_aspectRatio) {
      case PhotoAspectRatio.ratio1x1:
        return '1:1';
      case PhotoAspectRatio.ratio4x3:
        return '4:3';
      case PhotoAspectRatio.ratio16x9:
        return '16:9';
    }
  }

  int _getQualityHeightPixels() {
    switch (_qualityPreset) {
      case ImageQualityPreset.p1080:
        return 1080;
      case ImageQualityPreset.p720:
        return 720;
      case ImageQualityPreset.p480:
        return 480;
      case ImageQualityPreset.p360:
        return 360;
    }
  }

  String _getQualityLabel() {
    switch (_qualityPreset) {
      case ImageQualityPreset.p1080:
        return '1080p';
      case ImageQualityPreset.p720:
        return '720p';
      case ImageQualityPreset.p480:
        return '480p';
      case ImageQualityPreset.p360:
        return '360p';
    }
  }

  ResolutionPreset _getCameraResolutionPreset() {
    switch (_qualityPreset) {
      case ImageQualityPreset.p1080:
        return ResolutionPreset.high;
      case ImageQualityPreset.p720:
        return ResolutionPreset.high;
      case ImageQualityPreset.p480:
        return ResolutionPreset.medium;
      case ImageQualityPreset.p360:
        return ResolutionPreset.low;
    }
  }

  Future<void> _openGalleryAlbumBrowser() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _LatestPhotosGridScreen(
          initialConfig: _currentWatermarkConfig(),
          onConfigChanged: _applyWatermarkConfig,
        ),
      ),
    );
  }

  Future<void> _pickLogoImage() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        final permanentPath = await _AppPrefsStore.persistLogoFile(picked.path);
        if (!mounted) return;
        setState(() {
          _logoFilePath = permanentPath;
          _showLogo = true;
        });
        await _persistCurrentSettings();
      }
    } catch (e) {
      debugPrint('Gagal memilih logo: $e');
    }
  }

  Future<void> _pickManualDateTime() async {
    final DateTime base = _isManualTime ? _manualDateTime : DateTime.now();

    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (pickedDate == null || !mounted) return;

    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (pickedTime == null || !mounted) return;

    setState(() {
      _manualDateTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
        0,
      );
      _isManualTime = true;
      _showTime = true;
    });
    await _persistCurrentSettings();
  }

  Future<void> _showEditTextDialog({
    required String title,
    required String hint,
    required String currentValue,
    required ValueChanged<String> onSaved,
    bool autoEnableOnSave = true,
    VoidCallback? onEnableChanged,
  }) async {
    final controller = TextEditingController(text: currentValue);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result != null && mounted) {
      onSaved(result.trim());
      if (autoEnableOnSave && onEnableChanged != null) {
        onEnableChanged();
      }
      await _persistCurrentSettings();
    }
  }

  Future<void> _showSizePickerDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Ukuran & Warna Dasar Stempel'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ukuran Form',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                RadioListTile<StampFormSize>(
                  title: const Text('Kecil'),
                  value: StampFormSize.small,
                  groupValue: _formSize,
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() => _formSize = val);
                    setDialogState(() {});
                    unawaited(_persistCurrentSettings());
                  },
                ),
                RadioListTile<StampFormSize>(
                  title: const Text('Sedang'),
                  value: StampFormSize.medium,
                  groupValue: _formSize,
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() => _formSize = val);
                    setDialogState(() {});
                    unawaited(_persistCurrentSettings());
                  },
                ),
                RadioListTile<StampFormSize>(
                  title: const Text('Besar'),
                  value: StampFormSize.large,
                  groupValue: _formSize,
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() => _formSize = val);
                    setDialogState(() {});
                    unawaited(_persistCurrentSettings());
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  'Warna Dasar Tulisan',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: StampTextColor.values.map((c) {
                    final bool isSelected = _textColor == c;
                    return ChoiceChip(
                      selected: isSelected,
                      avatar: CircleAvatar(
                        radius: 8,
                        backgroundColor: _StampRenderer.resolveTextColor(c),
                      ),
                      label: Text(_StampRenderer.colorLabel(c)),
                      onSelected: (_) {
                        setState(() => _textColor = c);
                        setDialogState(() {});
                        unawaited(_persistCurrentSettings());
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                Text(
                  _textColor == StampTextColor.black
                      ? 'Shadow aktif: Putih (karena teks Hitam)'
                      : 'Shadow aktif: Hitam',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup'),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleDrawer(ActiveDrawer drawer) {
    setState(() {
      _openDrawer = _openDrawer == drawer ? ActiveDrawer.none : drawer;
    });
  }

  Future<void> _forceTorchOff({CameraController? controllerOverride}) async {
    final ctrl = controllerOverride ?? _controller;
    if (ctrl == null) return;
    try {
      if (ctrl.value.isInitialized) {
        await ctrl.setFlashMode(FlashMode.off);
      }
    } catch (e) {
      debugPrint('Gagal mematikan flash/torch: $e');
    }
  }

  Future<void> _activateBackTorchForCapture(CameraController ctrl) async {
    try {
      await ctrl.setFlashMode(FlashMode.torch);
      await Future.delayed(const Duration(milliseconds: 170));
    } catch (e) {
      debugPrint('Gagal menyalakan torch belakang saat shutter: $e');
    }
  }

  Future<void> _activateFrontScreenFlashForCapture() async {
    await _NativeBrightnessService.boostToMax();
    if (!mounted) return;
    setState(() => _screenFlashActive = true);
    await Future.delayed(const Duration(milliseconds: 220));
  }

  Future<void> _deactivateFrontScreenFlash() async {
    if (mounted && _screenFlashActive) {
      setState(() => _screenFlashActive = false);
    }
    await _NativeBrightnessService.restoreNormal();
  }

  Future<void> _initCameraByDirection(
    CameraLensDirection targetDir, {
    bool refreshList = false,
  }) async {
    if (_isInitializingCamera) return;
    if (mounted) {
      setState(() {
        _isInitializingCamera = true;
        _cameraErrorMessage = null;
        _screenFlashActive = false;
      });
    }
    await _NativeBrightnessService.restoreNormal();

    CameraController? newController;
    try {
      if (refreshList || cameras.isEmpty) {
        cameras = await availableCameras().timeout(const Duration(seconds: 8));
      }

      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _cameraErrorMessage =
                'Kamera tidak terdeteksi atau izin kamera belum diberikan.';
          });
        }
        return;
      }

      int foundIndex = cameras.indexWhere((c) => c.lensDirection == targetDir);
      if (foundIndex == -1) {
        foundIndex = 0;
      }

      await _disposeControllerSafely();
      await Future.delayed(const Duration(milliseconds: 120));

      newController = CameraController(
        cameras[foundIndex],
        _getCameraResolutionPreset(),
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await newController.initialize().timeout(const Duration(seconds: 10));
      try {
        await newController.setFlashMode(FlashMode.off);
      } catch (_) {}

      double minExp = -2.0;
      double maxExp = 2.0;
      try {
        minExp = await newController.getMinExposureOffset();
        maxExp = await newController.getMaxExposureOffset();
      } catch (_) {}

      if (!mounted) {
        await newController.dispose();
        return;
      }

      _controller = newController;
      setState(() {
        _currentLens = cameras[foundIndex].lensDirection;
        _screenFlashActive = false;
        _cameraErrorMessage = null;
        _minExposureOffset = minExp;
        _maxExposureOffset = maxExp;
        _currentExposureOffset = 0.0;
        _showFocusRing = false;
        _isDraggingExposure = false;
        _focusUiOffset = null;
      });
    } catch (e) {
      debugPrint('Gagal inisialisasi kamera: $e');
      if (newController != null) {
        try {
          await newController.dispose();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _cameraErrorMessage = 'Gagal membuka kamera: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isInitializingCamera = false;
        });
      }
    }
  }

  Future<void> _setQualityPreset(ImageQualityPreset preset) async {
    if (_qualityPreset == preset) return;
    setState(() => _qualityPreset = preset);
    await _persistCurrentSettings();
    await _initCameraByDirection(_currentLens, refreshList: false);
  }

  Future<void> _toggleFrontBackCamera() async {
    if (_isInitializingCamera || _isSaving || _isCoolingDown) return;
    _screenFlashActive = false;
    unawaited(_NativeBrightnessService.restoreNormal());
    unawaited(_forceTorchOff(controllerOverride: _controller));

    if (cameras.length < 2) {
      await _initCameraByDirection(CameraLensDirection.back, refreshList: true);
      return;
    }
    final CameraLensDirection nextDir =
        _currentLens == CameraLensDirection.back
            ? CameraLensDirection.front
            : CameraLensDirection.back;
    await _initCameraByDirection(nextDir, refreshList: false);
  }

  void _toggleFlash() {
    setState(() {
      _flashEnabled = !_flashEnabled;
      _screenFlashActive = false;
    });
    if (!_flashEnabled) {
      unawaited(_forceTorchOff(controllerOverride: _controller));
      unawaited(_NativeBrightnessService.restoreNormal());
    }
  }

  Future<void> _getLocation({bool requestIfDenied = true}) async {
    if (mounted) setState(() => _gpsCoordsText = 'Mencari GPS...');
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _gpsCoordsText = 'GPS Nonaktif');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestIfDenied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      if (mounted) setState(() => _gpsCoordsText = 'Izin Lokasi Ditolak');
      return;
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() => _gpsCoordsText = 'Izin Lokasi Permanen Ditolak');
      }
      return;
    }

    try {
      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (mounted) {
        setState(() {
          _gpsCoordsText =
              '${pos.latitude.toStringAsFixed(6)}°${pos.latitude < 0 ? 'S' : 'U'}, ${pos.longitude.toStringAsFixed(6)}°${pos.longitude < 0 ? 'B' : 'T'}';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _gpsCoordsText = 'Gagal membaca koordinat');
    }
  }

  String _buildTempFileName(String prefix, String uniqueId, String ext) {
    return '${prefix}_$uniqueId.$ext';
  }

  Future<void> _safeDeleteFile(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Gagal menghapus file temporer ($path): $e');
    }
  }

  Future<Uint8List> _buildCroppedRawJpgBytes({
    required String rawPhotoPath,
    required PhotoAspectRatio ratio,
    required int qualityHeight,
  }) async {
    final rawFile = File(rawPhotoPath);
    if (!await rawFile.exists() || await rawFile.length() == 0) {
      throw Exception('Berkas hasil kamera kosong');
    }
    final bytes = await rawFile.readAsBytes();
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.width <= 16 || decoded.height <= 16) {
      throw Exception('Gagal mendekode frame kamera');
    }

    final img.Image oriented = img.bakeOrientation(decoded);
    final int sw = oriented.width;
    final int sh = oriented.height;

    double targetRatio;
    if (ratio == PhotoAspectRatio.ratio1x1) {
      targetRatio = 1.0;
    } else if (ratio == PhotoAspectRatio.ratio4x3) {
      targetRatio = sh >= sw ? (3.0 / 4.0) : (4.0 / 3.0);
    } else {
      targetRatio = sh >= sw ? (9.0 / 16.0) : (16.0 / 9.0);
    }

    final double currentRatio = sw / sh;
    int cropW = sw;
    int cropH = sh;

    if ((currentRatio - targetRatio).abs() > 0.01) {
      if (currentRatio > targetRatio) {
        cropW = (sh * targetRatio).round();
      } else {
        cropH = (sw / targetRatio).round();
      }
    }

    cropW = max(1, min(sw, cropW));
    cropH = max(1, min(sh, cropH));

    final int offsetX = ((sw - cropW) / 2.0).floor();
    final int offsetY = ((sh - cropH) / 2.0).floor();

    img.Image cropped = img.copyCrop(
      oriented,
      x: offsetX,
      y: offsetY,
      width: cropW,
      height: cropH,
    );

    final int baseRef = min(cropped.width, cropped.height);
    if (baseRef > 0 && qualityHeight > 0 && baseRef > qualityHeight) {
      final double scaleFactor = qualityHeight / baseRef;
      final int outW = max(1, (cropped.width * scaleFactor).round());
      final int outH = max(1, (cropped.height * scaleFactor).round());
      cropped = img.copyResize(
        cropped,
        width: outW,
        height: outH,
        interpolation: img.Interpolation.linear,
      );
    }

    return Uint8List.fromList(img.encodeJpg(cropped, quality: 90));
  }

  Future<void> _onShutterPressed() async {
    if (_isSaving || _isCoolingDown || _isInitializingCamera) return;
    if (_countdownRemaining != null) {
      _cancelCountdown();
      return;
    }

    final int activeTimer = _normalizeTimer(_timerSeconds);
    if (activeTimer == 0) {
      await _executeTakePicture(usedTimer: 0);
      return;
    }

    setState(() {
      _openDrawer = ActiveDrawer.none;
      _countdownRemaining = activeTimer;
    });
    _countdownTimer?.cancel();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final int current = _countdownRemaining ?? 0;
      if (current <= 1) {
        timer.cancel();
        setState(() => _countdownRemaining = null);
        unawaited(_executeTakePicture(usedTimer: activeTimer));
      } else {
        final int nextVal = current - 1;
        setState(() => _countdownRemaining = nextVal);
      }
    });
  }

  Future<void> _executeTakePicture({required int usedTimer}) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
      _openDrawer = ActiveDrawer.none;
    });

    final bool useAutoFlashOnShutter = _flashEnabled;
    final bool isFront = _currentLens == CameraLensDirection.front;

    String? cameraRawPath;
    String? tempRawPath;
    String? tempStampedPath;
    int savedCount = 0;

    try {
      final DateTime activeDt = _getActiveDateTime();
      final String uniqueId =
          '${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(9999)}';

      if (useAutoFlashOnShutter) {
        if (isFront) {
          await _activateFrontScreenFlashForCapture();
        } else {
          await _activateBackTorchForCapture(ctrl);
        }
      }

      _triggerShutterBlink(milliseconds: 110);
      unawaited(_playShutterSoundIfEnabled());
      final XFile photo = await ctrl.takePicture();
      cameraRawPath = photo.path;

      if (isFront) {
        await _deactivateFrontScreenFlash();
      } else {
        await _forceTorchOff(controllerOverride: ctrl);
      }

      final Uint8List cleanRawJpgBytes = await _buildCroppedRawJpgBytes(
        rawPhotoPath: cameraRawPath,
        ratio: _aspectRatio,
        qualityHeight: _getQualityHeightPixels(),
      );

      final Uint8List stampedJpgBytes = await _StampRenderer.buildStampedJpgBytes(
        baseJpgBytes: cleanRawJpgBytes,
        activeDt: activeDt,
        cfg: _currentWatermarkConfig(),
      );

      final Directory tempDir = await getTemporaryDirectory();
      tempRawPath =
          '${tempDir.path}/${_buildTempFileName('clean_raw', uniqueId, 'jpg')}';
      tempStampedPath =
          '${tempDir.path}/${_buildTempFileName('with_stamp', uniqueId, 'jpg')}';

      await File(tempRawPath).writeAsBytes(cleanRawJpgBytes, flush: true);
      await File(tempStampedPath).writeAsBytes(stampedJpgBytes, flush: true);

      await Gal.putImage(tempRawPath);
      savedCount++;

      await Future.delayed(const Duration(milliseconds: 200));

      await Gal.putImage(tempStampedPath);
      savedCount++;

      _LatestPhotosGridScreen.invalidateCache();

      if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
        final String timerText = usedTimer == 0 ? '0s' : '${usedTimer}s';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Mode $timerText: $savedCount foto JPG tersimpan (${_getAspectRatioLabel()} • ${_getQualityLabel()})',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              savedCount > 0
                  ? '$savedCount dari 2 foto tersimpan. Detail error: $e'
                  : 'Gagal menyimpan foto: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      await _deactivateFrontScreenFlash();
      await _forceTorchOff(controllerOverride: ctrl);
      await _safeDeleteFile(cameraRawPath);
      await _safeDeleteFile(tempRawPath);
      await _safeDeleteFile(tempStampedPath);
      if (mounted) {
        setState(() {
          _isSaving = false;
          _screenFlashActive = false;
        });
        _startPostCaptureCooldown(milliseconds: 600);
      }
    }
  }

  Widget _buildFocusIndicatorOverlay(BoxConstraints box) {
    if (!_showFocusRing || _focusUiOffset == null) {
      return const SizedBox.shrink();
    }

    const double ringSize = 68;
    final double left = (_focusUiOffset!.dx - ringSize / 2)
        .clamp(8.0, max(8.0, box.maxWidth - ringSize - 8.0));
    final double top = (_focusUiOffset!.dy - ringSize / 2)
        .clamp(8.0, max(8.0, box.maxHeight - ringSize - 8.0));

    final bool canAdjustExposure = _maxExposureOffset > _minExposureOffset;
    final double sliderLeft = (left + ringSize + 8) <= (box.maxWidth - 36)
        ? (left + ringSize + 8)
        : max(8.0, left - 36);

    final double normalizedExp = canAdjustExposure
        ? ((_currentExposureOffset - _minExposureOffset) /
                (_maxExposureOffset - _minExposureOffset))
            .clamp(0.0, 1.0)
        : 0.5;

    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: Container(
              width: ringSize,
              height: ringSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFFFD000),
                  width: 2.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFFFD000),
                  ),
                ),
              ),
            ),
          ),
          if (canAdjustExposure)
            Positioned(
              left: sliderLeft,
              top: (top - 22).clamp(8.0, max(8.0, box.maxHeight - 122.0)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.wb_sunny_outlined,
                      size: 14,
                      color: Color(0xFFFFD000),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 82,
                      width: 14,
                      child: LayoutBuilder(
                        builder: (context, trackBox) {
                          final double trackH =
                              max(12.0, trackBox.maxHeight - 10);
                          final double thumbTop =
                              (1.0 - normalizedExp) * trackH;
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 2.5,
                                height: double.infinity,
                                color: Colors.white30,
                              ),
                              Positioned(
                                top: thumbTop,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFFFFD000),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProportionalPreview(CameraController ctrl) {
    final Size? previewSize = ctrl.value.previewSize;
    final bool isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    double sourceW = 4;
    double sourceH = 3;
    if (previewSize != null && previewSize.width > 0 && previewSize.height > 0) {
      if (isPortrait) {
        sourceW = min(previewSize.width, previewSize.height);
        sourceH = max(previewSize.width, previewSize.height);
      } else {
        sourceW = max(previewSize.width, previewSize.height);
        sourceH = min(previewSize.width, previewSize.height);
      }
    } else {
      final double ar =
          ctrl.value.aspectRatio > 0 ? ctrl.value.aspectRatio : (4 / 3);
      if (isPortrait) {
        sourceW = 300;
        sourceH = 300 * ar;
      } else {
        sourceW = 300 * ar;
        sourceH = 300;
      }
    }

    return LayoutBuilder(
      builder: (context, box) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) =>
              unawaited(_lockFocusAtPoint(details.localPosition, box)),
          onVerticalDragStart: (details) =>
              _handleVerticalExposureDragStart(details, box),
          onVerticalDragUpdate: (details) =>
              _handleVerticalExposureDragUpdate(details, box),
          onVerticalDragEnd: (_) => _handleVerticalExposureDragEnd(),
          onVerticalDragCancel: () => _handleVerticalExposureDragEnd(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: sourceW,
                    height: sourceH,
                    child: CameraPreview(ctrl),
                  ),
                ),
              ),
              if (_gridEnabled)
                IgnorePointer(
                  child: CustomPaint(
                    size: Size(box.maxWidth, box.maxHeight),
                    painter: _CameraGridPainter(),
                  ),
                ),
              _buildFocusIndicatorOverlay(box),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCameraViewport() {
    final ctrl = _controller;
    final bool isReady = ctrl != null &&
        ctrl.value.isInitialized &&
        !_isInitializingCamera;

    if (isReady) {
      return LayoutBuilder(
        builder: (context, outerBox) {
          final double ar = _getAspectRatioValue();
          double boxW = outerBox.maxWidth;
          double boxH = boxW / ar;
          if (outerBox.maxHeight.isFinite && boxH > outerBox.maxHeight) {
            boxH = outerBox.maxHeight;
            boxW = boxH * ar;
          }
          return SizedBox(
            width: boxW,
            height: boxH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildProportionalPreview(ctrl),
                if (_countdownRemaining != null)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '$_countdownRemaining',
                        style: const TextStyle(
                          color: Color(0xFFFFD000),
                          fontSize: 52,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                if (_isSaving || _isCoolingDown)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFFFD000),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isSaving ? 'Memproses...' : 'Menyiapkan...',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  bottom: 0,
                  right: 0,
                  child: _buildStampOverlayWidget(
                    activeDt: _getActiveDateTime(),
                    cfg: _currentWatermarkConfig(),
                    boxWidth: boxW,
                    boxHeight: boxH,
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    if (_cameraErrorMessage != null && !_isInitializingCamera) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _cameraErrorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _initCameraByDirection(
                CameraLensDirection.back,
                refreshList: true,
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('Muat Ulang Kamera'),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        const Text(
          'Mengganti kamera...',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () {
            _isInitializingCamera = false;
            _initCameraByDirection(CameraLensDirection.back, refreshList: true);
          },
          child: const Text('Reset Kamera'),
        ),
      ],
    );
  }

  Widget _buildTopBarAndDrawer() {
    final int displayedTimer = _normalizeTimer(_timerSeconds);

    return Container(
      width: double.infinity,
      color: Colors.black.withValues(alpha: 0.85),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: _openSettingsPage,
                  icon: const Icon(
                    Icons.settings,
                    size: 20,
                    color: Colors.white,
                  ),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Pengaturan',
                ),
                const SizedBox(width: 4),
                Text(
                  '${_getAspectRatioLabel()} • ${_getQualityLabel()}${displayedTimer > 0 ? ' • ${displayedTimer}s' : ' • 0s'}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: _toggleFlash,
                  icon: Icon(
                    _flashEnabled ? Icons.flash_on : Icons.flash_off,
                    size: 20,
                    color: _flashEnabled
                        ? const Color(0xFFFFD000)
                        : Colors.white,
                  ),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Blitz Otomatis Saat Shutter',
                ),
                IconButton(
                  onPressed: _toggleFrontBackCamera,
                  icon: Icon(
                    Icons.sync,
                    size: 20,
                    color: _currentLens == CameraLensDirection.front
                        ? const Color(0xFFFFD000)
                        : Colors.white,
                  ),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Rotasi Kamera',
                ),
                IconButton(
                  onPressed: () {
                    final next = displayedTimer == 0
                        ? 3
                        : (displayedTimer == 3 ? 5 : 0);
                    setState(() => _timerSeconds = next);
                  },
                  icon: Icon(
                    Icons.timer,
                    size: 20,
                    color: displayedTimer > 0
                        ? const Color(0xFFFFD000)
                        : Colors.white,
                  ),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Waktu Foto (Timer: 0s / 3s / 5s)',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerPanel() {
    if (_openDrawer != ActiveDrawer.watermarkEdit) {
      return const SizedBox.shrink();
    }

    final DateTime activeDt = _getActiveDateTime();
    final String timeSubLabel = _isManualTime
        ? '${_StampRenderer.formatHari(activeDt)}, ${_StampRenderer.formatTanggalLengkap(activeDt)} ${_StampRenderer.formatJamMenit(activeDt)} (Manual)'
        : '${_StampRenderer.formatHari(activeDt)}, ${_StampRenderer.formatTanggalLengkap(activeDt)} ${_StampRenderer.formatJamMenit(activeDt)}';

    final bool hasSavedLogo = _logoFilePath != null &&
        _logoFilePath!.isNotEmpty &&
        File(_logoFilePath!).existsSync();

    return Container(
      constraints: const BoxConstraints(maxHeight: 370),
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1D24),
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Sunting tanda air',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      setState(() => _openDrawer = ActiveDrawer.none),
                  icon: const Icon(Icons.close, color: Colors.white70),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 6),
            _WatermarkRowTile(
              icon: Icons.image_outlined,
              title: 'Logo',
              subtitle: hasSavedLogo
                  ? (_showLogo
                      ? 'Logo aktif (tersimpan permanen)'
                      : 'Logo tersimpan (ketuk untuk ganti)')
                  : 'Ketuk untuk memilih logo',
              value: _showLogo,
              onChanged: (val) {
                if (val && !hasSavedLogo) {
                  _pickLogoImage();
                } else {
                  setState(() => _showLogo = val);
                  unawaited(_persistCurrentSettings());
                }
              },
              onTapContent: _pickLogoImage,
            ),
            _WatermarkRowTile(
              icon: Icons.schedule_outlined,
              title: 'Waktu',
              subtitle: timeSubLabel,
              value: _showTime,
              onChanged: (val) {
                setState(() {
                  _showTime = val;
                  if (!val) {
                    _isManualTime = false;
                  }
                });
                unawaited(_persistCurrentSettings());
              },
              onTapContent: _pickManualDateTime,
            ),
            _WatermarkRowTile(
              icon: Icons.location_on_outlined,
              title: 'Alamat',
              subtitle: _customAddress.isNotEmpty
                  ? _customAddress
                  : 'Ketuk untuk mengedit alamat',
              value: _showAddress,
              onChanged: (val) {
                setState(() => _showAddress = val);
                unawaited(_persistCurrentSettings());
              },
              onTapContent: () => _showEditTextDialog(
                title: 'Edit Alamat',
                hint: 'Masukkan alamat lokasi...',
                currentValue: _customAddress,
                onSaved: (v) => setState(() => _customAddress = v),
                onEnableChanged: () => setState(() => _showAddress = true),
              ),
            ),
            _WatermarkRowTile(
              icon: Icons.public_outlined,
              title: 'Koordinat',
              subtitle: _gpsCoordsText,
              value: _showCoords,
              onChanged: (val) {
                setState(() => _showCoords = val);
                unawaited(_persistCurrentSettings());
                if (val) _getLocation(requestIfDenied: true);
              },
              onTapContent: () {
                setState(() => _showCoords = true);
                unawaited(_persistCurrentSettings());
                _getLocation(requestIfDenied: true);
              },
            ),
            _WatermarkRowTile(
              icon: Icons.notes_outlined,
              title: 'Perusahaan',
              subtitle: _companyText.isNotEmpty
                  ? _companyText
                  : 'Ketuk untuk mengedit',
              value: _showCompany,
              onChanged: (val) {
                setState(() => _showCompany = val);
                unawaited(_persistCurrentSettings());
              },
              onTapContent: () => _showEditTextDialog(
                title: 'Edit Perusahaan',
                hint: 'Nama instansi / perusahaan...',
                currentValue: _companyText,
                onSaved: (v) => setState(() => _companyText = v),
                onEnableChanged: () => setState(() => _showCompany = true),
              ),
            ),
            _WatermarkRowTile(
              icon: Icons.badge_outlined,
              title: 'Nama',
              subtitle: _personNameText.isNotEmpty
                  ? _personNameText
                  : 'Ketuk untuk mengedit',
              value: _showPersonName,
              onChanged: (val) {
                setState(() => _showPersonName = val);
                unawaited(_persistCurrentSettings());
              },
              onTapContent: () => _showEditTextDialog(
                title: 'Edit Nama',
                hint: 'Nama petugas / pengguna...',
                currentValue: _personNameText,
                onSaved: (v) => setState(() => _personNameText = v),
                onEnableChanged: () => setState(() => _showPersonName = true),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _showSizePickerDialog,
                    child: Text(
                      'Warna & Ukuran (${_StampRenderer.colorLabel(_textColor)} • ${_getFormSizeLabel()})',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E6BFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () =>
                        setState(() => _openDrawer = ActiveDrawer.none),
                    child: const Text(
                      'Selesai',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final bool counting = _countdownRemaining != null;
    final bool shutterLocked = _isSaving || _isCoolingDown;

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.only(top: 6, bottom: 16, left: 16, right: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Foto',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _BottomActionIcon(
                icon: Icons.photo_library_outlined,
                label: 'Album',
                active: false,
                onTap: _openGalleryAlbumBrowser,
              ),
              GestureDetector(
                onTap: shutterLocked ? null : _onShutterPressed,
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: counting ? const Color(0xFFFFD000) : Colors.white,
                      width: 4,
                    ),
                  ),
                  padding: const EdgeInsets.all(5),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: shutterLocked
                          ? Colors.grey
                          : (counting ? const Color(0xFFFFD000) : Colors.white),
                    ),
                    child: shutterLocked
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : (counting
                            ? Center(
                                child: Text(
                                  '${_countdownRemaining}s',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              )
                            : null),
                  ),
                ),
              ),
              _BottomActionIcon(
                icon: Icons.edit_outlined,
                label: 'Sunting',
                active: _openDrawer == ActiveDrawer.watermarkEdit,
                onTap: () => _toggleDrawer(ActiveDrawer.watermarkEdit),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _countdownTimer?.cancel();
    _cooldownTimer?.cancel();
    _shutterBlinkTimer?.cancel();
    _focusRingTimer?.cancel();
    unawaited(_NativeBrightnessService.restoreNormal());
    final ctrl = _controller;
    _controller = null;
    if (ctrl != null) {
      unawaited(ctrl.setFlashMode(FlashMode.off));
      ctrl.dispose();
    }
    unawaited(_ShutterAudioService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildTopBarAndDrawer(),
                Expanded(
                  child: Center(
                    child: _buildCameraViewport(),
                  ),
                ),
                _buildDrawerPanel(),
                _buildBottomBar(),
              ],
            ),
            if (_shutterBlinkActive)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
              ),
            if (_screenFlashActive)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: const Color(0xFFFFFFFF),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MediaEntry {
  final File file;
  final DateTime modified;

  const _MediaEntry({
    required this.file,
    required this.modified,
  });
}

class _MonthlyPhotoSection {
  final int year;
  final int month;
  final String monthName;
  final String title;
  final List<_MediaEntry> entries;
  final int startGlobalIndex;

  const _MonthlyPhotoSection({
    required this.year,
    required this.month,
    required this.monthName,
    required this.title,
    required this.entries,
    required this.startGlobalIndex,
  });
}

class _LatestPhotosGridScreen extends StatefulWidget {
  final _WatermarkConfig initialConfig;
  final ValueChanged<_WatermarkConfig> onConfigChanged;

  const _LatestPhotosGridScreen({
    required this.initialConfig,
    required this.onConfigChanged,
  });

  static List<_MediaEntry>? _cachedEntries;

  static void invalidateCache() {
    _cachedEntries = null;
  }

  @override
  State<_LatestPhotosGridScreen> createState() => _LatestPhotosGridScreenState();
}

class _LatestPhotosGridScreenState extends State<_LatestPhotosGridScreen> {
  static const int _maxFilesScan = 6000;
  static const int _initialVisibleCount = 45;
  static const int _pageBatchSize = 45;
  static const int _minCollagePhotos = 2;
  static const int _maxCollagePhotos = 6;
  static const double _headerHeight = 42.0;
  static const double _gridSpacing = 3.0;
  static const double _gridHorizontalPadding = 4.0;
  static const MethodChannel _mediaStoreChannel =
      MethodChannel('timestamp_by_putra/media_store');

  static const List<String> _bulanIndo = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  static const List<String> _bulanSingkatIndo = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];

  late _WatermarkConfig _config;
  late final ScrollController _scrollController;
  bool _isLoading = true;
  bool _isDeleting = false;
  List<_MediaEntry> _entries = [];
  List<_MonthlyPhotoSection> _fullSections = [];
  int _visibleCount = 0;
  double _cachedViewportWidth = 390.0;

  bool _selectionMode = false;
  final List<String> _selectedPaths = [];

  final ValueNotifier<double> _scrubFractionNotifier =
      ValueNotifier<double>(0.0);
  final ValueNotifier<bool> _scrubVisibleNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _scrubDraggingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String?> _scrubDatePillNotifier =
      ValueNotifier<String?>(null);

  Timer? _hideScrubberTimer;
  double? _scrubTargetFraction;
  bool _isProgrammaticJumping = false;

  static const Set<String> _photoExts = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.heic',
    '.heif',
  };

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
    _scrollController = ScrollController()..addListener(_onScroll);
    final cached = _LatestPhotosGridScreen._cachedEntries;
    if (cached != null && cached.isNotEmpty) {
      _entries = cached;
      _fullSections = _buildMonthlySections(_entries);
      _visibleCount = min(_initialVisibleCount, _entries.length);
      _isLoading = false;
    } else {
      _loadAllPhotos();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final double w = MediaQuery.of(context).size.width;
    if (w > 0) {
      _cachedViewportWidth = w;
    }
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) {
        _selectedPaths.clear();
      }
    });
  }

  void _enterSelectionWithPath(String path) {
    setState(() {
      _selectionMode = true;
      if (!_selectedPaths.contains(path)) {
        _selectedPaths.add(path);
      }
    });
  }

  void _toggleSelectPath(String path) {
    setState(() {
      final int idx = _selectedPaths.indexOf(path);
      if (idx != -1) {
        _selectedPaths.removeAt(idx);
      } else {
        _selectedPaths.add(path);
      }
    });
  }

  Future<void> _openCollageStageFromSelection() async {
    final int count = _selectedPaths.length;
    if (count < _minCollagePhotos || count > _maxCollagePhotos) {
      return;
    }
    final List<File> chosenFiles = _selectedPaths.map((p) => File(p)).toList();

    final bool? savedNew = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _CollageStagePreviewScreen(
          selectedFiles: chosenFiles,
          initialConfig: _config,
        ),
      ),
    );

    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selectedPaths.clear();
    });

    if (savedNew == true) {
      _LatestPhotosGridScreen.invalidateCache();
      await _loadAllPhotos(forceRefresh: true);
    }
  }

  Future<void> _deleteSelectedToTrash() async {
    if (_selectedPaths.isEmpty || _isDeleting) return;
    final List<String> targets = _selectedPaths.toList();
    final bool ok = await _TrashService.confirmMoveToTrash(
      context,
      count: targets.length,
    );
    if (!ok || !mounted) return;

    setState(() => _isDeleting = true);
    final int moved = await _TrashService.moveFilesToTrash(targets);
    _LatestPhotosGridScreen.invalidateCache();
    await _loadAllPhotos(forceRefresh: true);

    if (!mounted) return;
    setState(() {
      _isDeleting = false;
      _selectionMode = false;
      _selectedPaths.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$moved foto dipindahkan ke sampah'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _scheduleScrubberHide({int milliseconds = 1500}) {
    _hideScrubberTimer?.cancel();
    if (_scrubDraggingNotifier.value) return;
    _hideScrubberTimer = Timer(Duration(milliseconds: milliseconds), () {
      if (!mounted || _scrubDraggingNotifier.value) return;
      _scrubVisibleNotifier.value = false;
      _scrubDatePillNotifier.value = null;
    });
  }

  double _cellExtent(double viewportWidth) {
    final double usableW = max(
      120.0,
      viewportWidth - (_gridHorizontalPadding * 2.0) - (_gridSpacing * 2.0),
    );
    return usableW / 3.0;
  }

  double _totalEstimatedScrollHeight(double viewportWidth) {
    if (_fullSections.isEmpty || _entries.isEmpty) return 0.0;
    final double cell = _cellExtent(viewportWidth);
    final double rowStride = cell + _gridSpacing;
    double y = 0.0;
    for (final sec in _fullSections) {
      final int rows = (sec.entries.length / 3.0).ceil();
      y += _headerHeight + (rows * rowStride) + _gridSpacing;
    }
    return y;
  }

  double _offsetForGlobalIndex(int globalIndex, double viewportWidth) {
    if (_fullSections.isEmpty || _entries.isEmpty) return 0.0;
    final int clampedIdx = globalIndex.clamp(0, _entries.length - 1);
    final double cell = _cellExtent(viewportWidth);
    final double rowStride = cell + _gridSpacing;
    double y = 0.0;

    for (final sec in _fullSections) {
      final int secEnd = sec.startGlobalIndex + sec.entries.length;
      if (clampedIdx < secEnd) {
        final int localIdx = max(0, clampedIdx - sec.startGlobalIndex);
        final int rowIdx = localIdx ~/ 3;
        return y + _headerHeight + (rowIdx * rowStride);
      } else {
        final int rows = (sec.entries.length / 3.0).ceil();
        y += _headerHeight + (rows * rowStride) + _gridSpacing;
      }
    }

    return y;
  }

  int _globalIndexAtOffset(double scrollY, double viewportWidth) {
    if (_fullSections.isEmpty || _entries.isEmpty || scrollY <= 0) return 0;
    final double cell = _cellExtent(viewportWidth);
    final double rowStride = cell + _gridSpacing;
    double y = 0.0;

    for (final sec in _fullSections) {
      final int rows = (sec.entries.length / 3.0).ceil();
      final double secHeight = _headerHeight + (rows * rowStride) + _gridSpacing;
      if (scrollY <= y + secHeight) {
        final double insideSec = max(0.0, scrollY - y - _headerHeight);
        final int rowIdx =
            (insideSec / rowStride).floor().clamp(0, max(0, rows - 1));
        final int idx = sec.startGlobalIndex + (rowIdx * 3);
        return idx.clamp(0, _entries.length - 1);
      }
      y += secHeight;
    }

    return _entries.length - 1;
  }

  String _formatDatePill(DateTime dt) {
    if (dt.millisecondsSinceEpoch <= 0) return 'Foto';
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime targetDay = DateTime(dt.year, dt.month, dt.day);
    final int diffDays = today.difference(targetDay).inDays;

    if (diffDays == 0) return 'Hari ini';
    if (diffDays == 1) return 'Kemarin';

    final String mShort = (dt.month >= 1 && dt.month <= 12)
        ? _bulanSingkatIndo[dt.month - 1]
        : 'Bln ${dt.month}';
    return '${dt.day} $mShort ${dt.year}';
  }

  String _resolveDateLabelAtFraction(double fraction) {
    if (_entries.isEmpty) return 'Terbaru';
    final int idx = (fraction * (_entries.length - 1))
        .round()
        .clamp(0, _entries.length - 1);
    return _formatDatePill(_entries[idx].modified);
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isProgrammaticJumping) return;
    final pos = _scrollController.position;
    final total = _entries.length;
    if (total <= 0) return;

    if (!_scrubDraggingNotifier.value) {
      final int currentIdx =
          _globalIndexAtOffset(pos.pixels, _cachedViewportWidth);
      final double frac = total <= 1
          ? 0.0
          : (currentIdx / (total - 1)).clamp(
              0.0,
              pos.maxScrollExtent > 0
                  ? (pos.pixels / pos.maxScrollExtent).clamp(0.0, 1.0)
                  : 0.0,
            );

      _scrubFractionNotifier.value = frac;
      if (!_scrubVisibleNotifier.value && pos.pixels > 6) {
        _scrubVisibleNotifier.value = true;
      }
      _scheduleScrubberHide();

      if (_visibleCount < total && pos.pixels >= pos.maxScrollExtent - 400) {
        setState(() {
          _visibleCount = min(total, _visibleCount + _pageBatchSize);
        });
      }
    }
  }

  void _previewScrubAtFraction(double frac) {
    if (_entries.isEmpty) return;
    final double clampedFrac = frac.clamp(0.0, 1.0);
    _scrubTargetFraction = clampedFrac;
    _scrubFractionNotifier.value = clampedFrac;
    _scrubVisibleNotifier.value = true;
    _scrubDraggingNotifier.value = true;
    _scrubDatePillNotifier.value = _resolveDateLabelAtFraction(clampedFrac);
  }

  void _commitScrubJump() {
    _scrubDraggingNotifier.value = false;
    final double frac =
        (_scrubTargetFraction ?? _scrubFractionNotifier.value).clamp(0.0, 1.0);
    _scrubTargetFraction = null;

    if (!_scrollController.hasClients || _entries.isEmpty) {
      _scheduleScrubberHide();
      return;
    }

    final int targetIdx =
        (frac * (_entries.length - 1)).round().clamp(0, _entries.length - 1);
    final int neededVisible =
        min(_entries.length, max(_visibleCount, targetIdx + 24));

    final double rawTargetOffset =
        _offsetForGlobalIndex(targetIdx, _cachedViewportWidth);

    double clampTargetToBounds(double target) {
      if (!_scrollController.hasClients) return 0.0;
      final pos = _scrollController.position;
      final double viewportH = pos.viewportDimension > 0
          ? pos.viewportDimension
          : max(200.0, MediaQuery.of(context).size.height - 140.0);
      final double estimatedMax = max(
        pos.maxScrollExtent,
        _totalEstimatedScrollHeight(_cachedViewportWidth) - viewportH,
      );
      return target.clamp(0.0, max(0.0, estimatedMax));
    }

    void runJump(double offset) {
      if (!mounted || !_scrollController.hasClients) return;
      _isProgrammaticJumping = true;
      try {
        _scrollController.jumpTo(offset);
      } catch (_) {}
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isProgrammaticJumping = false;
      });
    }

    if (neededVisible > _visibleCount) {
      _isProgrammaticJumping = true;
      setState(() => _visibleCount = neededVisible);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) {
          _isProgrammaticJumping = false;
          return;
        }
        final double safeAfterExpand = clampTargetToBounds(rawTargetOffset);
        runJump(safeAfterExpand);
      });
    } else {
      runJump(clampTargetToBounds(rawTargetOffset));
    }

    _scheduleScrubberHide();
  }

  bool _isPhotoFile(String path) {
    final lower = path.toLowerCase();
    for (final ext in _photoExts) {
      if (lower.endsWith(ext)) return true;
    }
    return false;
  }

  Future<void> _ensureMediaPermissions() async {
    if (!Platform.isAndroid) return;
    try {
      await _mediaStoreChannel.invokeMethod('requestMediaPermissions');
    } catch (e) {
      debugPrint('requestMediaPermissions belum tersedia/gagal: $e');
    }
  }

  Future<List<_MediaEntry>> _queryMediaStoreNative() async {
    if (!Platform.isAndroid) return const [];
    try {
      final List<dynamic>? rawList =
          await _mediaStoreChannel.invokeMethod<List<dynamic>>('getAllImages');
      if (rawList == null || rawList.isEmpty) return const [];

      final List<_MediaEntry> results = [];
      final Set<String> seen = {};
      for (final item in rawList) {
        if (results.length >= _maxFilesScan) break;
        final String path = item?.toString().trim() ?? '';
        if (path.isEmpty || !_isPhotoFile(path) || seen.contains(path)) {
          continue;
        }
        seen.add(path);

        final File f = File(path);
        results.add(
          _MediaEntry(
            file: f,
            modified: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );
      }
      return results;
    } catch (e) {
      debugPrint('MediaStore native belum tersedia/aktif: $e');
      return const [];
    }
  }

  Future<List<_MediaEntry>> _scanDirectoriesFallback() async {
    final List<_MediaEntry> allEntries = [];
    final List<Directory> candidateDirs = [];

    if (Platform.isAndroid) {
      for (final p in [
        '/storage/emulated/0/DCIM',
        '/storage/emulated/0/Pictures',
        '/storage/emulated/0/Download',
      ]) {
        final d = Directory(p);
        if (await d.exists()) candidateDirs.add(d);
      }
    }

    final Set<String> visitedPaths = {};

    Future<void> scanDir(Directory dir, {int depth = 0}) async {
      if (depth > 3 || allEntries.length >= _maxFilesScan) return;
      try {
        await for (final entity in dir.list(followLinks: false)) {
          if (allEntries.length >= _maxFilesScan) break;
          final path = entity.path;
          if (visitedPaths.contains(path)) continue;
          visitedPaths.add(path);

          if (entity is Directory) {
            final baseName = path.split(Platform.pathSeparator).last;
            if (baseName.startsWith('.')) continue;
            await scanDir(entity, depth: depth + 1);
          } else if (entity is File && _isPhotoFile(path)) {
            allEntries.add(
              _MediaEntry(
                file: entity,
                modified: DateTime.fromMillisecondsSinceEpoch(0),
              ),
            );
          }
        }
      } catch (_) {}
    }

    for (final d in candidateDirs) {
      await scanDir(d);
    }
    return allEntries;
  }

  Future<void> _hydrateModifiedDates(List<_MediaEntry> rawList) async {
    const int chunkSize = 80;
    for (int i = 0; i < rawList.length; i += chunkSize) {
      if (!mounted) return;
      final int end = min(rawList.length, i + chunkSize);
      for (int j = i; j < end; j++) {
        try {
          final st = rawList[j].file.statSync();
          rawList[j] = _MediaEntry(
            file: rawList[j].file,
            modified: st.modified,
          );
        } catch (_) {}
      }
      if (i > 0 && i % 240 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  Future<void> _loadAllPhotos({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _LatestPhotosGridScreen._cachedEntries != null &&
        _LatestPhotosGridScreen._cachedEntries!.isNotEmpty) {
      if (mounted) {
        final cached = _LatestPhotosGridScreen._cachedEntries!;
        setState(() {
          _entries = cached;
          _fullSections = _buildMonthlySections(cached);
          _visibleCount = min(_initialVisibleCount, _entries.length);
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    await _ensureMediaPermissions();

    List<_MediaEntry> collected = await _queryMediaStoreNative();
    if (collected.isEmpty) {
      collected = await _scanDirectoriesFallback();
    }

    await _hydrateModifiedDates(collected);
    collected.sort((a, b) => b.modified.compareTo(a.modified));
    _LatestPhotosGridScreen._cachedEntries = collected;

    if (!mounted) return;
    setState(() {
      _entries = collected;
      _fullSections = _buildMonthlySections(collected);
      _visibleCount = min(_initialVisibleCount, _entries.length);
      _isLoading = false;
    });
  }

  List<_MonthlyPhotoSection> _buildMonthlySections(List<_MediaEntry> source) {
    if (source.isEmpty) return const [];

    final Map<String, List<_MediaEntry>> grouped = {};
    final List<String> orderedKeys = [];

    for (final entry in source) {
      final int y = entry.modified.year;
      final int m = entry.modified.month;
      final String key = '$y-${m.toString().padLeft(2, '0')}';
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
        orderedKeys.add(key);
      }
      grouped[key]!.add(entry);
    }

    final List<_MonthlyPhotoSection> result = [];
    int cursor = 0;

    for (final key in orderedKeys) {
      final list = grouped[key]!;
      final firstDt = list.first.modified;
      final String monthName = (firstDt.month >= 1 && firstDt.month <= 12)
          ? _bulanIndo[firstDt.month - 1]
          : 'Bulan ${firstDt.month}';
      result.add(
        _MonthlyPhotoSection(
          year: firstDt.year,
          month: firstDt.month,
          monthName: monthName,
          title: '$monthName ${firstDt.year} (${list.length})',
          entries: list,
          startGlobalIndex: cursor,
        ),
      );
      cursor += list.length;
    }

    return result;
  }

  List<_MonthlyPhotoSection> _buildVisibleSections(int limit) {
    if (_fullSections.isEmpty || limit <= 0) return const [];
    final int safeLimit = limit.clamp(0, _entries.length);
    final List<_MonthlyPhotoSection> visible = [];

    for (final sec in _fullSections) {
      if (sec.startGlobalIndex >= safeLimit) break;
      final int takeCount =
          min(sec.entries.length, safeLimit - sec.startGlobalIndex);
      if (takeCount <= 0) continue;
      visible.add(
        _MonthlyPhotoSection(
          year: sec.year,
          month: sec.month,
          monthName: sec.monthName,
          title: sec.title,
          entries: sec.entries.take(takeCount).toList(),
          startGlobalIndex: sec.startGlobalIndex,
        ),
      );
    }

    return visible;
  }

  Future<void> _openPhotoWatermarkEditorAtIndex(int initialIndex) async {
    final List<File> allFiles = _entries.map((e) => e.file).toList();
    if (allFiles.isEmpty) return;

    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _GalleryWatermarkEditorScreen(
          photoFiles: allFiles,
          initialIndex: initialIndex.clamp(0, allFiles.length - 1),
          initialConfig: _config,
          onConfigUpdated: (updatedCfg) {
            if (!mounted) return;
            setState(() => _config = updatedCfg);
            widget.onConfigChanged(updatedCfg);
          },
        ),
      ),
    );

    if (changed == true && mounted) {
      _LatestPhotosGridScreen.invalidateCache();
      await _loadAllPhotos(forceRefresh: true);
    }
  }

  Widget _buildRightFastScrubber() {
    if (_entries.length < 6) return const SizedBox.shrink();

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, box) {
          const double thumbHeight = 62.0;
          const double thumbWidth = 32.0;
          final double trackHeight = max(80.0, box.maxHeight - 24.0);
          final double usableHeight = max(1.0, trackHeight - thumbHeight);

          return Stack(
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: _scrubDraggingNotifier,
                builder: (context, isDragging, _) {
                  if (!isDragging) return const SizedBox.shrink();
                  return ValueListenableBuilder<String?>(
                    valueListenable: _scrubDatePillNotifier,
                    builder: (context, pillText, _) {
                      if (pillText == null) return const SizedBox.shrink();
                      return Positioned(
                        top: 16,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF282C36),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: const Color(0xFFFFD000),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            child: Text(
                              pillText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              Positioned(
                right: 0,
                top: 12,
                height: trackHeight,
                width: 52,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragStart: (details) {
                    final frac =
                        (details.localPosition.dy / trackHeight).clamp(0.0, 1.0);
                    _previewScrubAtFraction(frac);
                  },
                  onVerticalDragUpdate: (details) {
                    final frac =
                        (details.localPosition.dy / trackHeight).clamp(0.0, 1.0);
                    _previewScrubAtFraction(frac);
                  },
                  onVerticalDragEnd: (_) => _commitScrubJump(),
                  onVerticalDragCancel: () => _commitScrubJump(),
                  onTapDown: (details) {
                    final frac =
                        (details.localPosition.dy / trackHeight).clamp(0.0, 1.0);
                    _previewScrubAtFraction(frac);
                    _commitScrubJump();
                  },
                  child: ValueListenableBuilder<double>(
                    valueListenable: _scrubFractionNotifier,
                    builder: (context, frac, _) {
                      final double thumbTop =
                          (frac * usableHeight).clamp(0.0, usableHeight);
                      return ValueListenableBuilder<bool>(
                        valueListenable: _scrubDraggingNotifier,
                        builder: (context, isDragging, __) {
                          return Stack(
                            children: [
                              Positioned(
                                right: 8,
                                top: thumbTop,
                                child: Container(
                                  width: thumbWidth,
                                  height: thumbHeight,
                                  decoration: BoxDecoration(
                                    color: isDragging
                                        ? const Color(0xFFFFD000)
                                        : const Color(0xFF2E3440),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isDragging
                                          ? Colors.white
                                          : Colors.white38,
                                      width: 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            Colors.black.withValues(alpha: 0.5),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.arrow_drop_up,
                                        size: 18,
                                        color: isDragging
                                            ? Colors.black
                                            : Colors.white,
                                      ),
                                      Icon(
                                        Icons.arrow_drop_down,
                                        size: 18,
                                        color: isDragging
                                            ? Colors.black
                                            : Colors.white,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSelectionActionBar() {
    if (!_selectionMode || _selectedPaths.isEmpty) {
      return const SizedBox.shrink();
    }

    final int count = _selectedPaths.length;
    final bool overCollageLimit = count > _maxCollagePhotos;
    final bool canCollage =
        count >= _minCollagePhotos && count <= _maxCollagePhotos;

    return Container(
      color: const Color(0xFF14171E),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Text(
                overCollageLimit
                    ? '$count foto dipilih • Kolase maks. 6 foto'
                    : '$count foto dipilih',
                style: TextStyle(
                  color: overCollageLimit
                      ? const Color(0xFFFFB74D)
                      : Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              onPressed: _isDeleting ? null : _deleteSelectedToTrash,
              icon: const Icon(Icons.delete_outline, color: Color(0xFFFF5A5F)),
              tooltip: 'Pindahkan ke Sampah',
            ),
            const SizedBox(width: 6),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor:
                    (canCollage && !_isDeleting)
                        ? const Color(0xFFFFD000)
                        : Colors.white12,
                foregroundColor:
                    (canCollage && !_isDeleting)
                        ? Colors.black
                        : Colors.white38,
                disabledBackgroundColor: Colors.white12,
                disabledForegroundColor: Colors.white38,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed:
                  (canCollage && !_isDeleting)
                      ? _openCollageStageFromSelection
                      : null,
              child: Text(
                overCollageLimit
                    ? 'Kolase (Maks 6)'
                    : (count < _minCollagePhotos
                        ? 'Kolase'
                        : 'Kolase ($count)'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hideScrubberTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _scrubFractionNotifier.dispose();
    _scrubVisibleNotifier.dispose();
    _scrubDraggingNotifier.dispose();
    _scrubDatePillNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double w = MediaQuery.of(context).size.width;
    if (w > 0) _cachedViewportWidth = w;

    final total = _entries.length;
    final sections = _buildVisibleSections(_visibleCount);
    final hasMore = _visibleCount < total;
    final int selectedCount = _selectedPaths.length;

    final String appBarTitle = _selectionMode
        ? (selectedCount > 0 ? '$selectedCount ditandai' : 'Tandai foto')
        : (total > 0 ? 'Terbaru ($total)' : 'Terbaru');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          appBarTitle,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (total > 0)
            TextButton(
              onPressed: _isDeleting ? null : _toggleSelectionMode,
              child: Text(
                _selectionMode ? 'Batal' : 'Tandai',
                style: TextStyle(
                  color:
                      _selectionMode ? const Color(0xFFFFD000) : Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildSelectionActionBar(),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFFFFD000),
              ),
            )
          : total == 0
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.photo_library_outlined,
                          size: 48,
                          color: Colors.white54,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Foto belum terbaca. Pastikan izin akses foto/media sudah diizinkan.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: () => _loadAllPhotos(forceRefresh: true),
                          child: const Text('Muat Ulang'),
                        ),
                      ],
                    ),
                  ),
                )
              : Stack(
                  children: [
                    RefreshIndicator(
                      onRefresh: () => _loadAllPhotos(forceRefresh: true),
                      child: CustomScrollView(
                        controller: _scrollController,
                        cacheExtent: 360,
                        slivers: [
                          for (final sec in sections) ...[
                            SliverToBoxAdapter(
                              child: SizedBox(
                                height: _headerHeight,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 14, 12, 8),
                                  child: Text(
                                    sec.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: _gridHorizontalPadding,
                              ),
                              sliver: SliverGrid(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: _gridSpacing,
                                  mainAxisSpacing: _gridSpacing,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (ctx, idx) {
                                    final File file = sec.entries[idx].file;
                                    final int globalIdx =
                                        sec.startGlobalIndex + idx;
                                    final int selIndex =
                                        _selectedPaths.indexOf(file.path);
                                    final bool isChecked = selIndex != -1;
                                    final int orderBadge =
                                        (isChecked && selIndex < _maxCollagePhotos)
                                            ? (selIndex + 1)
                                            : 0;

                                    return GestureDetector(
                                      onLongPress: () =>
                                          _enterSelectionWithPath(file.path),
                                      onTap: () {
                                        if (_selectionMode) {
                                          _toggleSelectPath(file.path);
                                        } else {
                                          _openPhotoWatermarkEditorAtIndex(
                                            globalIdx,
                                          );
                                        }
                                      },
                                      child: ColoredBox(
                                        color: const Color(0xFF14171E),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            Image.file(
                                              file,
                                              cacheWidth: 96,
                                              filterQuality: FilterQuality.low,
                                              fit: BoxFit.cover,
                                              gaplessPlayback: true,
                                              errorBuilder: (_, __, ___) =>
                                                  const ColoredBox(
                                                color: Color(0xFF1C2029),
                                                child: Icon(
                                                  Icons.broken_image_outlined,
                                                  color: Colors.white54,
                                                ),
                                              ),
                                            ),
                                            if (isChecked)
                                              Container(
                                                color: Colors.black
                                                    .withValues(alpha: 0.34),
                                              ),
                                            if (_selectionMode || isChecked)
                                              Positioned(
                                                top: 6,
                                                right: 6,
                                                child: Container(
                                                  width: 24,
                                                  height: 24,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: isChecked
                                                        ? const Color(
                                                            0xFFFFD000,
                                                          )
                                                        : Colors.black
                                                            .withValues(
                                                              alpha: 0.45,
                                                            ),
                                                    border: Border.all(
                                                      color: Colors.white,
                                                      width: 1.5,
                                                    ),
                                                  ),
                                                  child: isChecked
                                                      ? Center(
                                                          child: orderBadge > 0
                                                              ? Text(
                                                                  '$orderBadge',
                                                                  style:
                                                                      const TextStyle(
                                                                    color:
                                                                        Colors
                                                                            .black,
                                                                    fontSize: 12,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w800,
                                                                  ),
                                                                )
                                                              : const Icon(
                                                                  Icons.check,
                                                                  size: 14,
                                                                  color: Colors
                                                                      .black,
                                                                ),
                                                        )
                                                      : null,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  childCount: sec.entries.length,
                                  addAutomaticKeepAlives: false,
                                  addRepaintBoundaries: true,
                                ),
                              ),
                            ),
                          ],
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: hasMore
                                    ? TextButton.icon(
                                        onPressed: () {
                                          setState(() {
                                            _visibleCount = min(
                                              total,
                                              _visibleCount + _pageBatchSize,
                                            );
                                          });
                                        },
                                        icon: const Icon(Icons.expand_more),
                                        label: Text(
                                          'Muat lagi ($_visibleCount dari $total foto)',
                                        ),
                                      )
                                    : Text(
                                        'Semua foto dimuat ($total foto)',
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildRightFastScrubber(),
                  ],
                ),
    );
  }
}

class _CollageStagePreviewScreen extends StatefulWidget {
  final List<File> selectedFiles;
  final _WatermarkConfig initialConfig;

  const _CollageStagePreviewScreen({
    required this.selectedFiles,
    required this.initialConfig,
  });

  @override
  State<_CollageStagePreviewScreen> createState() =>
      _CollageStagePreviewScreenState();
}

class _CollageStagePreviewScreenState
    extends State<_CollageStagePreviewScreen> {
  static const int _minSlots = 2;
  static const int _maxSlots = 6;
  static const double _previewGap = 4.0;
  static const double _previewOuterPad = 4.0;

  final ImagePicker _picker = ImagePicker();
  final Random _rng = Random();

  late int _slotCount;
  late CollageLayoutId _layoutId;
  late List<File?> _slots;
  late List<Offset> _slotPanNorms;
  final Map<String, Size> _photoDimsCache = {};
  int? _draggingSlotIndex;
  bool _hasDirtyChanges = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final List<File> initial = widget.selectedFiles.take(_maxSlots).toList();
    _slotCount = initial.length.clamp(_minSlots, _maxSlots);
    _layoutId = _CollageLayoutCatalog.defaultForCount(_slotCount).id;
    _slots = List<File?>.generate(
      _slotCount,
      (i) => i < initial.length ? initial[i] : null,
    );
    _slotPanNorms = List<Offset>.generate(_slotCount, (_) => Offset.zero);
    for (final f in _slots) {
      if (f != null) unawaited(_cacheImageDimensions(f));
    }
  }

  Future<void> _cacheImageDimensions(File file) async {
    if (_photoDimsCache.containsKey(file.path)) return;
    try {
      if (!await file.exists()) return;
      final Uint8List bytes = await file.readAsBytes();
      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null || decoded.width <= 0 || decoded.height <= 0) return;
      final img.Image oriented = img.bakeOrientation(decoded);
      if (!mounted) return;
      setState(() {
        _photoDimsCache[file.path] = Size(
          oriented.width.toDouble(),
          oriented.height.toDouble(),
        );
      });
    } catch (_) {}
  }

  Offset _panForSlot(int index) {
    if (index < 0 || index >= _slotPanNorms.length) return Offset.zero;
    return _slotPanNorms[index];
  }

  void _setPanForSlot(int index, Offset nextPan) {
    if (index < 0 || index >= _slotPanNorms.length) return;
    _slotPanNorms[index] = Offset(
      nextPan.dx.clamp(-1.0, 1.0),
      nextPan.dy.clamp(-1.0, 1.0),
    );
  }

  void _resetPanForSlot(int index) {
    if (index < 0 || index >= _slotPanNorms.length) return;
    setState(() {
      _slotPanNorms[index] = Offset.zero;
      _hasDirtyChanges = true;
    });
  }

  void _handleSlotPanDrag(
    int index,
    Offset deltaPx,
    double slotW,
    double slotH,
  ) {
    if (_isSaving || index < 0 || index >= _slots.length) return;
    final File? file = _slots[index];
    if (file == null) return;

    final Size? dims = _photoDimsCache[file.path];
    if (dims == null || dims.width <= 0 || dims.height <= 0) {
      unawaited(_cacheImageDimensions(file));
      return;
    }
    if (slotW <= 1 || slotH <= 1) return;

    final double srcRatio = dims.width / dims.height;
    final double dstRatio = slotW / slotH;

    double maxShiftX = 0.0;
    double maxShiftY = 0.0;

    if (srcRatio > dstRatio + 0.005) {
      final double renderedW = slotH * srcRatio;
      maxShiftX = max(0.0, (renderedW - slotW) / 2.0);
    } else if (dstRatio > srcRatio + 0.005) {
      final double renderedH = slotW / srcRatio;
      maxShiftY = max(0.0, (renderedH - slotH) / 2.0);
    }

    if (maxShiftX <= 0.5 && maxShiftY <= 0.5) return;

    final Offset currentNorm = _panForSlot(index);
    final double currentShiftX = currentNorm.dx * maxShiftX;
    final double currentShiftY = currentNorm.dy * maxShiftY;

    final double nextShiftX =
        (currentShiftX + deltaPx.dx).clamp(-maxShiftX, maxShiftX);
    final double nextShiftY =
        (currentShiftY + deltaPx.dy).clamp(-maxShiftY, maxShiftY);

    final double nextNormX =
        maxShiftX > 0.5 ? (nextShiftX / maxShiftX).clamp(-1.0, 1.0) : 0.0;
    final double nextNormY =
        maxShiftY > 0.5 ? (nextShiftY / maxShiftY).clamp(-1.0, 1.0) : 0.0;

    setState(() {
      _setPanForSlot(index, Offset(nextNormX, nextNormY));
      _hasDirtyChanges = true;
    });
  }

  void _changeSlotCount(int delta) {
    if (_isSaving) return;
    final int nextCount = (_slotCount + delta).clamp(_minSlots, _maxSlots);
    if (nextCount == _slotCount) return;

    final List<File?> nextSlots = List<File?>.filled(nextCount, null);
    final List<Offset> nextPans = List<Offset>.filled(nextCount, Offset.zero);
    for (int i = 0; i < nextCount; i++) {
      if (i < _slots.length) {
        nextSlots[i] = _slots[i];
        nextPans[i] = _slotPanNorms[i];
      } else if (i < widget.selectedFiles.length) {
        nextSlots[i] = widget.selectedFiles[i];
        unawaited(_cacheImageDimensions(widget.selectedFiles[i]));
      }
    }

    final List<_CollageLayoutDef> matchingLayouts =
        _CollageLayoutCatalog.layoutsForCount(nextCount);
    final CollageLayoutId nextLayout =
        matchingLayouts.any((l) => l.id == _layoutId)
            ? _layoutId
            : matchingLayouts.first.id;

    setState(() {
      _slotCount = nextCount;
      _slots = nextSlots;
      _slotPanNorms = nextPans;
      _layoutId = nextLayout;
      _hasDirtyChanges = true;
    });
  }

  void _selectLayout(CollageLayoutId id) {
    if (_isSaving || _layoutId == id) return;
    setState(() {
      _layoutId = id;
      _hasDirtyChanges = true;
    });
  }

  Future<void> _pickPhotoForSlot(int slotIndex) async {
    if (_isSaving || slotIndex < 0 || slotIndex >= _slots.length) return;
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
      );
      if (picked != null && mounted) {
        final File newFile = File(picked.path);
        unawaited(_cacheImageDimensions(newFile));
        setState(() {
          _slots[slotIndex] = newFile;
          _slotPanNorms[slotIndex] = Offset.zero;
          _hasDirtyChanges = true;
        });
      }
    } catch (e) {
      debugPrint('Gagal memilih foto slot kolase: $e');
    }
  }

  Future<bool> _confirmCancel() async {
    if (_isSaving) return false;
    if (!_hasDirtyChanges) {
      Navigator.of(context).pop(false);
      return true;
    }

    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D24),
        title: const Text('Batalkan kolase?'),
        content: const Text(
          'Perubahan kolase saat ini akan dibuang dan kembali ke album.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Lanjut mengedit'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD9383A),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Buang'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      Navigator.of(context).pop(false);
      return true;
    }
    return false;
  }

  int _targetHdCanvasWidth(int count) {
    if (count <= 3) return 1600;
    if (count <= 5) return 1800;
    return 2048;
  }

  img.Image? _loadCroppedSlotImage({
    required File file,
    required int dstW,
    required int dstH,
    required Offset panNorm,
  }) {
    if (!file.existsSync()) return null;
    final Uint8List bytes = file.readAsBytesSync();
    if (bytes.isEmpty) return null;

    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.width <= 1 || decoded.height <= 1) {
      return null;
    }

    final img.Image oriented = img.bakeOrientation(decoded);
    final int sw = oriented.width;
    final int sh = oriented.height;

    final double targetRatio = dstW / max(1, dstH);
    final double srcRatio = sw / max(1, sh);

    int cropW = sw;
    int cropH = sh;
    if ((srcRatio - targetRatio).abs() > 0.005) {
      if (srcRatio > targetRatio) {
        cropW = max(1, (sh * targetRatio).round());
      } else {
        cropH = max(1, (sw / targetRatio).round());
      }
    }

    cropW = min(sw, max(1, cropW));
    cropH = min(sh, max(1, cropH));

    final double halfRangeX = max(0.0, (sw - cropW) / 2.0);
    final double halfRangeY = max(0.0, (sh - cropH) / 2.0);

    final double centerX = (sw / 2.0) - (panNorm.dx.clamp(-1.0, 1.0) * halfRangeX);
    final double centerY = (sh / 2.0) - (panNorm.dy.clamp(-1.0, 1.0) * halfRangeY);

    final int cropX = (centerX - (cropW / 2.0))
        .round()
        .clamp(0, max(0, sw - cropW));
    final int cropY = (centerY - (cropH / 2.0))
        .round()
        .clamp(0, max(0, sh - cropH));

    final img.Image cropped = img.copyCrop(
      oriented,
      x: cropX,
      y: cropY,
      width: min(sw - cropX, cropW),
      height: min(sh - cropY, cropH),
    );

    return img.copyResize(
      cropped,
      width: max(1, dstW),
      height: max(1, dstH),
      interpolation: img.Interpolation.linear,
    );
  }

  Future<void> _saveHdCollage() async {
    if (_isSaving) return;

    final List<File> activeFiles =
        _slots.whereType<File>().take(_slotCount).toList();
    if (activeFiles.length < _slotCount || _slotCount < _minSlots) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Isi semua slot foto terlebih dahulu sebelum menyimpan'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() => _isSaving = true);
    String? tempOutPath;

    try {
      final _CollageLayoutDef layoutDef =
          _CollageLayoutCatalog.findById(_layoutId);
      final int canvasW = _targetHdCanvasWidth(_slotCount);
      final int canvasH = max(
        600,
        (canvasW / layoutDef.aspectRatio).round(),
      );

      final double hdPad = max(6.0, (canvasW * 0.01).roundToDouble());
      final double hdGap = max(6.0, (canvasW * 0.01).roundToDouble());

      final List<_CollageSlotRect> rects = _CollageLayoutCatalog.computeSlots(
        layoutId: _layoutId,
        canvasW: canvasW.toDouble(),
        canvasH: canvasH.toDouble(),
        gap: hdGap,
        outerPadding: hdPad,
      );

      final img.Image canvasImg = img.Image(
        width: canvasW,
        height: canvasH,
        numChannels: 4,
      );
      canvasImg.clear(img.ColorRgba8(18, 21, 28, 255));

      for (int i = 0; i < rects.length && i < activeFiles.length; i++) {
        final _CollageSlotRect r = rects[i];
        final int dx = r.x.round();
        final int dy = r.y.round();
        final int dw = max(1, r.w.round());
        final int dh = max(1, r.h.round());

        final img.Image? tile = _loadCroppedSlotImage(
          file: activeFiles[i],
          dstW: dw,
          dstH: dh,
          panNorm: _panForSlot(i),
        );
        if (tile != null) {
          img.compositeImage(
            canvasImg,
            tile,
            dstX: dx,
            dstY: dy,
          );
        }
        await Future<void>.delayed(Duration.zero);
      }

      final Uint8List jpgBytes =
          Uint8List.fromList(img.encodeJpg(canvasImg, quality: 92));

      final Directory tempDir = await getTemporaryDirectory();
      final String stampId =
          '${DateTime.now().millisecondsSinceEpoch}_${_rng.nextInt(9999)}';
      tempOutPath = '${tempDir.path}/collage_hd_$stampId.jpg';
      await File(tempOutPath).writeAsBytes(jpgBytes, flush: true);

      await Gal.putImage(tempOutPath);
      _LatestPhotosGridScreen.invalidateCache();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Kolase HD (${canvasW}x$canvasH) tersimpan ke galeri',
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menyimpan kolase: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (tempOutPath != null) {
        try {
          final f = File(tempOutPath);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildCollageCanvasPreview() {
    final _CollageLayoutDef layoutDef =
        _CollageLayoutCatalog.findById(_layoutId);

    return LayoutBuilder(
      builder: (context, outerBox) {
        final double maxW = max(120.0, outerBox.maxWidth - 24.0);
        final double maxH = max(140.0, outerBox.maxHeight - 16.0);
        final double targetRatio = layoutDef.aspectRatio;

        double boxW = maxW;
        double boxH = boxW / targetRatio;
        if (boxH > maxH) {
          boxH = maxH;
          boxW = boxH * targetRatio;
        }

        final List<_CollageSlotRect> rects = _CollageLayoutCatalog.computeSlots(
          layoutId: _layoutId,
          canvasW: boxW,
          canvasH: boxH,
          gap: _previewGap,
          outerPadding: _previewOuterPad,
        );

        return Center(
          child: Container(
            width: boxW,
            height: boxH,
            decoration: BoxDecoration(
              color: const Color(0xFF12151C),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: Stack(
              children: [
                for (final r in rects)
                  Positioned(
                    left: r.x,
                    top: r.y,
                    width: r.w,
                    height: r.h,
                    child: _buildSlotTile(r.index, r.w, r.h),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSlotTile(int index, double w, double h) {
    final File? file = index < _slots.length ? _slots[index] : null;
    final Offset panNorm = _panForSlot(index);
    final bool isDraggingThis = _draggingSlotIndex == index;

    return GestureDetector(
      onTap: _isSaving ? null : () => _pickPhotoForSlot(index),
      onDoubleTap: _isSaving || file == null
          ? null
          : () => _resetPanForSlot(index),
      onPanStart: _isSaving || file == null
          ? null
          : (_) {
              unawaited(_cacheImageDimensions(file));
              setState(() => _draggingSlotIndex = index);
            },
      onPanUpdate: _isSaving || file == null
          ? null
          : (details) =>
              _handleSlotPanDrag(index, details.delta, w, h),
      onPanEnd: (_) {
        if (_draggingSlotIndex == index && mounted) {
          setState(() => _draggingSlotIndex = null);
        }
      },
      onPanCancel: () {
        if (_draggingSlotIndex == index && mounted) {
          setState(() => _draggingSlotIndex = null);
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Container(
          color: const Color(0xFF1C212B),
          foregroundDecoration: isDraggingThis
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: const Color(0xFFFFD000),
                    width: 2.0,
                  ),
                )
              : null,
          child: file != null
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      file,
                      cacheWidth: max(220, (w * 2.0).round()),
                      fit: BoxFit.cover,
                      alignment: Alignment(panNorm.dx, panNorm.dy),
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Color(0xFFFFD000),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add_photo_alternate_outlined,
                      color: Color(0xFFFFD000),
                      size: 26,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tambah ${index + 1}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildControlsDock() {
    final List<_CollageLayoutDef> layoutsForCurrent =
        _CollageLayoutCatalog.layoutsForCount(_slotCount);

    return Container(
      color: const Color(0xFF14171E),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Jumlah Foto: $_slotCount (2–6)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: (_isSaving || _slotCount <= _minSlots)
                          ? null
                          : () => _changeSlotCount(-1),
                      icon: const Icon(Icons.remove, size: 18),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Kurangi foto',
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: (_isSaving || _slotCount >= _maxSlots)
                          ? null
                          : () => _changeSlotCount(1),
                      icon: const Icon(Icons.add, size: 18),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Tambah foto',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              'Seret gambar untuk mengatur posisi • Ketuk 2x untuk tengah',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: layoutsForCurrent.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, idx) {
                  final def = layoutsForCurrent[idx];
                  final bool selected = def.id == _layoutId;
                  return ChoiceChip(
                    selected: selected,
                    selectedColor: const Color(0xFFFFD000),
                    backgroundColor: const Color(0xFF222732),
                    labelStyle: TextStyle(
                      color: selected ? Colors.black : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    label: Text(def.label),
                    onSelected: _isSaving ? null : (_) => _selectLayout(def.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool allFilled =
        _slots.whereType<File>().length >= _slotCount && _slotCount >= _minSlots;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_confirmCancel());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            tooltip: 'Batal',
            onPressed: _isSaving ? null : () => unawaited(_confirmCancel()),
          ),
          title: Text(
            'Kolase ($_slotCount foto)',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: (allFilled && !_isSaving)
                      ? const Color(0xFFFFD000)
                      : Colors.white12,
                  foregroundColor: (allFilled && !_isSaving)
                      ? Colors.black
                      : Colors.white38,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: (allFilled && !_isSaving) ? _saveHdCollage : null,
                child: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Text(
                        'Simpan',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(child: _buildCollageCanvasPreview()),
              _buildControlsDock(),
            ],
          ),
        ),
      ),
    );
  }
}

class _GalleryWatermarkEditorScreen extends StatefulWidget {
  final List<File> photoFiles;
  final int initialIndex;
  final _WatermarkConfig initialConfig;
  final ValueChanged<_WatermarkConfig> onConfigUpdated;

  const _GalleryWatermarkEditorScreen({
    required this.photoFiles,
    required this.initialIndex,
    required this.initialConfig,
    required this.onConfigUpdated,
  });

  @override
  State<_GalleryWatermarkEditorScreen> createState() =>
      _GalleryWatermarkEditorScreenState();
}

class _GalleryWatermarkEditorScreenState
    extends State<_GalleryWatermarkEditorScreen> {
  late _WatermarkConfig _cfg;
  late List<File> _files;
  late int _currentIndex;
  late PageController _pageController;

  final ImagePicker _picker = ImagePicker();
  DateTime _nowClock = DateTime.now();
  Timer? _clockTimer;
  bool _stampVisible = false;
  bool _editorDrawerOpen = false;
  bool _isSaving = false;
  bool _anyChanged = false;
  bool _isClosingEmpty = false;
  final Map<String, double> _aspectRatioCache = {};

  @override
  void initState() {
    super.initState();
    _cfg = widget.initialConfig;
    _files = List<File>.from(widget.photoFiles);
    _currentIndex = _files.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, _files.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    _stampVisible = false;
    if (_files.isNotEmpty) {
      _resolvePhotoAspectRatio(_files[_currentIndex]);
    }
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!_cfg.isManualTime) {
        setState(() => _nowClock = DateTime.now());
      }
    });
  }

  File? get _currentFile {
    if (_files.isEmpty) return null;
    return _files[_currentIndex.clamp(0, _files.length - 1)];
  }

  Future<void> _resolvePhotoAspectRatio(File file) async {
    if (_aspectRatioCache.containsKey(file.path)) return;
    try {
      if (!await file.exists()) return;
      final size = await _readImageDimensionsFast(file);
      if (size == null || size.width <= 0 || size.height <= 0) return;
      if (!mounted) return;
      setState(() {
        _aspectRatioCache[file.path] = size.width / size.height;
      });
    } catch (_) {}
  }

  Future<Size?> _readImageDimensionsFast(File file) async {
    try {
      final raf = await file.open(mode: FileMode.read);
      try {
        final len = await raf.length();
        final int readLen = min(len, 65536);
        final Uint8List head = await raf.read(readLen);

        if (head.length >= 24 &&
            head[0] == 0x89 &&
            head[1] == 0x50 &&
            head[2] == 0x4E &&
            head[3] == 0x47) {
          final int w = (head[16] << 24) |
              (head[17] << 16) |
              (head[18] << 8) |
              head[19];
          final int h = (head[20] << 24) |
              (head[21] << 16) |
              (head[22] << 8) |
              head[23];
          if (w > 0 && h > 0) {
            return Size(w.toDouble(), h.toDouble());
          }
        }

        if (head.length >= 4 && head[0] == 0xFF && head[1] == 0xD8) {
          int i = 2;
          while (i + 9 < head.length) {
            if (head[i] != 0xFF) {
              i++;
              continue;
            }
            final int marker = head[i + 1];
            if (marker == 0xD9 || marker == 0xDA) break;
            if (marker == 0xC0 ||
                marker == 0xC1 ||
                marker == 0xC2 ||
                marker == 0xC3 ||
                marker == 0xC5 ||
                marker == 0xC6 ||
                marker == 0xC7 ||
                marker == 0xC9 ||
                marker == 0xCA ||
                marker == 0xCB ||
                marker == 0xCD ||
                marker == 0xCE ||
                marker == 0xCF) {
              final int h = (head[i + 5] << 8) | head[i + 6];
              final int w = (head[i + 7] << 8) | head[i + 8];
              if (w > 0 && h > 0) {
                return Size(w.toDouble(), h.toDouble());
              }
            }
            if (i + 3 >= head.length) break;
            final int segLen = (head[i + 2] << 8) | head[i + 3];
            if (segLen < 2) break;
            i += 2 + segLen;
          }
        }
      } finally {
        await raf.close();
      }
    } catch (_) {}

    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded != null && decoded.width > 0 && decoded.height > 0) {
        final oriented = img.bakeOrientation(decoded);
        return Size(oriented.width.toDouble(), oriented.height.toDouble());
      }
    } catch (_) {}
    return null;
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  DateTime _activeDateTime() {
    return _cfg.isManualTime ? _cfg.manualDateTime : _nowClock;
  }

  void _updateCfg(_WatermarkConfig next) {
    setState(() => _cfg = next);
    widget.onConfigUpdated(next);
    unawaited(_AppPrefsStore.updateFromWatermarkConfig(next));
  }

  String _sizeLabel() {
    switch (_cfg.formSize) {
      case StampFormSize.small:
        return 'Kecil';
      case StampFormSize.medium:
        return 'Sedang';
      case StampFormSize.large:
        return 'Besar';
    }
  }

  Future<void> _pickLogo() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        final permanentPath = await _AppPrefsStore.persistLogoFile(picked.path);
        if (!mounted) return;
        _updateCfg(
          _cfg.copyWith(
            logoFilePath: permanentPath,
            showLogo: true,
          ),
        );
        setState(() => _stampVisible = true);
      }
    } catch (e) {
      debugPrint('Gagal memilih logo di editor album: $e');
    }
  }

  Future<void> _pickManualDateTime() async {
    final DateTime base =
        _cfg.isManualTime ? _cfg.manualDateTime : DateTime.now();

    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (pickedDate == null || !mounted) return;

    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (pickedTime == null || !mounted) return;

    _updateCfg(
      _cfg.copyWith(
        manualDateTime: DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
          0,
        ),
        isManualTime: true,
        showTime: true,
      ),
    );
    setState(() => _stampVisible = true);
  }

  Future<void> _editFieldDialog({
    required String title,
    required String hint,
    required String initialValue,
    required void Function(String trimmed) applyText,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result != null && mounted) {
      applyText(result.trim());
      setState(() => _stampVisible = true);
    }
  }

  Future<void> _pickSizeDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Ukuran & Warna Dasar Stempel'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ukuran Form',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                RadioListTile<StampFormSize>(
                  title: const Text('Kecil'),
                  value: StampFormSize.small,
                  groupValue: _cfg.formSize,
                  onChanged: (val) {
                    if (val == null) return;
                    _updateCfg(_cfg.copyWith(formSize: val));
                    setDialogState(() {});
                  },
                ),
                RadioListTile<StampFormSize>(
                  title: const Text('Sedang'),
                  value: StampFormSize.medium,
                  groupValue: _cfg.formSize,
                  onChanged: (val) {
                    if (val == null) return;
                    _updateCfg(_cfg.copyWith(formSize: val));
                    setDialogState(() {});
                  },
                ),
                RadioListTile<StampFormSize>(
                  title: const Text('Besar'),
                  value: StampFormSize.large,
                  groupValue: _cfg.formSize,
                  onChanged: (val) {
                    if (val == null) return;
                    _updateCfg(_cfg.copyWith(formSize: val));
                    setDialogState(() {});
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  'Warna Dasar Tulisan',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: StampTextColor.values.map((c) {
                    final bool isSelected = _cfg.textColor == c;
                    return ChoiceChip(
                      selected: isSelected,
                      avatar: CircleAvatar(
                        radius: 8,
                        backgroundColor: _StampRenderer.resolveTextColor(c),
                      ),
                      label: Text(_StampRenderer.colorLabel(c)),
                      onSelected: (_) {
                        _updateCfg(_cfg.copyWith(textColor: c));
                        setDialogState(() {});
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                Text(
                  _cfg.textColor == StampTextColor.black
                      ? 'Shadow aktif: Putih (karena teks Hitam)'
                      : 'Shadow aktif: Hitam',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup'),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleStampFromTemplateButton() {
    setState(() {
      _stampVisible = !_stampVisible;
    });
  }

  Future<void> _deleteCurrentPhotoToTrash() async {
    final File? target = _currentFile;
    if (target == null || _isSaving || _isClosingEmpty) return;

    final bool confirmed = await _TrashService.confirmMoveToTrash(
      context,
      count: 1,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isSaving = true);
    final int moved = await _TrashService.moveFilesToTrash([target.path]);
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (moved <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal memindahkan foto ke sampah'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _anyChanged = true;
    _LatestPhotosGridScreen.invalidateCache();

    final int removedIdx = _currentIndex;
    final List<File> nextFiles = List<File>.from(_files)..removeAt(removedIdx);

    if (nextFiles.isEmpty) {
      _isClosingEmpty = true;
      setState(() {
        _files = const [];
        _currentIndex = 0;
        _editorDrawerOpen = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pop(true);
      });
      return;
    }

    final int nextIdx =
        removedIdx >= nextFiles.length ? nextFiles.length - 1 : removedIdx;

    setState(() {
      _files = nextFiles;
      _currentIndex = nextIdx;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.jumpToPage(nextIdx);
      _resolvePhotoAspectRatio(nextFiles[nextIdx]);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Foto dipindahkan ke sampah'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _saveStampedPhotoToGallery() async {
    final File? activeFile = _currentFile;
    if (_isSaving || activeFile == null) return;
    setState(() => _isSaving = true);

    String? tempOutPath;
    try {
      if (!await activeFile.exists()) {
        throw Exception('File foto tidak ditemukan');
      }
      final Uint8List rawBytes = await activeFile.readAsBytes();
      final Uint8List outputBytes = _stampVisible
          ? await _StampRenderer.buildStampedJpgBytes(
              baseJpgBytes: rawBytes,
              activeDt: _activeDateTime(),
              cfg: _cfg,
            )
          : rawBytes;

      final Directory tempDir = await getTemporaryDirectory();
      tempOutPath =
          '${tempDir.path}/album_stamp_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(tempOutPath).writeAsBytes(outputBytes, flush: true);

      await Gal.putImage(tempOutPath);
      _LatestPhotosGridScreen.invalidateCache();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _stampVisible
                ? 'Foto bertanda air berhasil disimpan ke galeri'
                : 'Foto berhasil disimpan ke galeri',
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menyimpan tanda air foto: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (tempOutPath != null) {
        try {
          final f = File(tempOutPath);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildEditDrawer() {
    if (!_editorDrawerOpen) return const SizedBox.shrink();

    final DateTime dt = _activeDateTime();
    final String timeSub =
        '${_StampRenderer.formatHari(dt)}, ${_StampRenderer.formatTanggalLengkap(dt)} ${_StampRenderer.formatJamMenit(dt)}${_cfg.isManualTime ? ' (Manual)' : ''}';

    final bool hasSavedLogo = _cfg.logoFilePath != null &&
        _cfg.logoFilePath!.isNotEmpty &&
        File(_cfg.logoFilePath!).existsSync();

    return Container(
      constraints: const BoxConstraints(maxHeight: 360),
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1D24),
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Sunting tanda air',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _editorDrawerOpen = false),
                  icon: const Icon(Icons.close, color: Colors.white70),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            _WatermarkRowTile(
              icon: Icons.image_outlined,
              title: 'Logo',
              subtitle: hasSavedLogo
                  ? (_cfg.showLogo
                      ? 'Logo aktif (tersimpan permanen)'
                      : 'Logo tersimpan (ketuk untuk ganti)')
                  : 'Ketuk untuk memilih logo',
              value: _cfg.showLogo,
              onChanged: (val) {
                if (val && !hasSavedLogo) {
                  _pickLogo();
                } else {
                  _updateCfg(_cfg.copyWith(showLogo: val));
                  if (val) setState(() => _stampVisible = true);
                }
              },
              onTapContent: _pickLogo,
            ),
            _WatermarkRowTile(
              icon: Icons.schedule_outlined,
              title: 'Waktu',
              subtitle: timeSub,
              value: _cfg.showTime,
              onChanged: (val) {
                _updateCfg(
                  _cfg.copyWith(
                    showTime: val,
                    isManualTime: val ? _cfg.isManualTime : false,
                  ),
                );
                if (val) setState(() => _stampVisible = true);
              },
              onTapContent: _pickManualDateTime,
            ),
            _WatermarkRowTile(
              icon: Icons.location_on_outlined,
              title: 'Alamat',
              subtitle: _cfg.customAddress.isNotEmpty
                  ? _cfg.customAddress
                  : 'Ketuk untuk mengedit alamat',
              value: _cfg.showAddress,
              onChanged: (val) {
                _updateCfg(_cfg.copyWith(showAddress: val));
                if (val) setState(() => _stampVisible = true);
              },
              onTapContent: () => _editFieldDialog(
                title: 'Edit Alamat',
                hint: 'Masukkan alamat lokasi...',
                initialValue: _cfg.customAddress,
                applyText: (v) => _updateCfg(
                  _cfg.copyWith(customAddress: v, showAddress: true),
                ),
              ),
            ),
            _WatermarkRowTile(
              icon: Icons.public_outlined,
              title: 'Koordinat',
              subtitle: _cfg.gpsCoordsText,
              value: _cfg.showCoords,
              onChanged: (val) {
                _updateCfg(_cfg.copyWith(showCoords: val));
                if (val) setState(() => _stampVisible = true);
              },
              onTapContent: () => _editFieldDialog(
                title: 'Edit Koordinat',
                hint: 'Contoh: 3.695432°S, 128.181405°T',
                initialValue: _cfg.gpsCoordsText,
                applyText: (v) => _updateCfg(
                  _cfg.copyWith(gpsCoordsText: v, showCoords: true),
                ),
              ),
            ),
            _WatermarkRowTile(
              icon: Icons.notes_outlined,
              title: 'Perusahaan',
              subtitle: _cfg.companyText.isNotEmpty
                  ? _cfg.companyText
                  : 'Ketuk untuk mengedit',
              value: _cfg.showCompany,
              onChanged: (val) {
                _updateCfg(_cfg.copyWith(showCompany: val));
                if (val) setState(() => _stampVisible = true);
              },
              onTapContent: () => _editFieldDialog(
                title: 'Edit Perusahaan',
                hint: 'Nama instansi / perusahaan...',
                initialValue: _cfg.companyText,
                applyText: (v) => _updateCfg(
                  _cfg.copyWith(companyText: v, showCompany: true),
                ),
              ),
            ),
            _WatermarkRowTile(
              icon: Icons.badge_outlined,
              title: 'Nama',
              subtitle: _cfg.personNameText.isNotEmpty
                  ? _cfg.personNameText
                  : 'Ketuk untuk mengedit',
              value: _cfg.showPersonName,
              onChanged: (val) {
                _updateCfg(_cfg.copyWith(showPersonName: val));
                if (val) setState(() => _stampVisible = true);
              },
              onTapContent: () => _editFieldDialog(
                title: 'Edit Nama',
                hint: 'Nama petugas / pengguna...',
                initialValue: _cfg.personNameText,
                applyText: (v) => _updateCfg(
                  _cfg.copyWith(personNameText: v, showPersonName: true),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _pickSizeDialog,
                    child: Text(
                      'Warna & Ukuran (${_StampRenderer.colorLabel(_cfg.textColor)} • ${_sizeLabel()})',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E6BFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => setState(() => _editorDrawerOpen = false),
                    child: const Text(
                      'Selesai',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        automaticallyImplyLeading: false,
        leading: TextButton(
          onPressed:
              _isSaving ? null : () => Navigator.of(context).pop(_anyChanged),
          child: const Text(
            'Batal',
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
        ),
        leadingWidth: 74,
        centerTitle: true,
        title: Text(
          _files.isEmpty
              ? 'Tanda air foto'
              : '${_currentIndex + 1} / ${_files.length}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: _isSaving ? null : _deleteCurrentPhotoToTrash,
            icon: const Icon(Icons.delete_outline, color: Color(0xFFFF5A5F)),
            tooltip: 'Pindahkan ke Sampah',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1E6BFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _isSaving ? null : _saveStampedPhotoToGallery,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Selesai',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _files.isEmpty
                  ? const SizedBox.shrink()
                  : PageView.builder(
                      controller: _pageController,
                      itemCount: _files.length,
                      onPageChanged: (idx) {
                        setState(() => _currentIndex = idx);
                        _resolvePhotoAspectRatio(_files[idx]);
                      },
                      itemBuilder: (context, idx) {
                        final File itemFile = _files[idx];
                        final double ratio =
                            _aspectRatioCache[itemFile.path] ?? (3.0 / 4.0);
                        return Center(
                          child: LayoutBuilder(
                            builder: (context, outerBox) {
                              final double safeRatio =
                                  ratio > 0 ? ratio : (3.0 / 4.0);
                              double boxW = outerBox.maxWidth;
                              double boxH = boxW / safeRatio;
                              if (outerBox.maxHeight.isFinite &&
                                  boxH > outerBox.maxHeight) {
                                boxH = outerBox.maxHeight;
                                boxW = boxH * safeRatio;
                              }
                              return SizedBox(
                                width: boxW,
                                height: boxH,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.file(
                                      itemFile,
                                      fit: BoxFit.fill,
                                      width: boxW,
                                      height: boxH,
                                      errorBuilder: (_, __, ___) =>
                                          const Center(
                                        child: Text(
                                          'Gagal memuat foto',
                                          style: TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (_stampVisible)
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        bottom: 0,
                                        child: _buildStampOverlayWidget(
                                          activeDt: _activeDateTime(),
                                          cfg: _cfg,
                                          boxWidth: boxW,
                                          boxHeight: boxH,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
            _buildEditDrawer(),
            Container(
              color: Colors.black,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            _stampVisible ? Colors.black : Colors.white,
                        backgroundColor: _stampVisible
                            ? const Color(0xFFFFD000)
                            : Colors.transparent,
                        side: BorderSide(
                          color: _stampVisible
                              ? const Color(0xFFFFD000)
                              : Colors.white24,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed:
                          _isSaving ? null : _toggleStampFromTemplateButton,
                      icon: Icon(
                        _stampVisible
                            ? Icons.check_circle_outline
                            : Icons.dashboard_customize_outlined,
                        size: 18,
                      ),
                      label: const Text('Templat'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF252932),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _isSaving
                          ? null
                          : () => setState(
                                () => _editorDrawerOpen = !_editorDrawerOpen,
                              ),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Sunting tanda air'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniChipButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MiniChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFD000) : const Color(0xFF252932),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _WatermarkRowTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback onTapContent;

  const _WatermarkRowTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.onTapContent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 22, color: const Color(0xFF4EA8FF)),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: onTapContent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
          InkWell(
            onTap: onTapContent,
            child: const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.chevron_right, size: 18, color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomActionIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _BottomActionIcon({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg = active ? const Color(0xFFFFD000) : Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: fg, size: 24),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

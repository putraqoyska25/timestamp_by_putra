import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Error kamera: $e');
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

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  String _locationText = 'Mencari GPS...';
  String _customNote = '';
  bool _isSaving = false;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _initCamera();
    _getLocation();
  }

  Future<void> _initCamera() async {
    if (cameras.isEmpty) return;
    _controller = CameraController(
      cameras[0],
      ResolutionPreset.high,
      enableAudio: false,
    );
    await _controller!.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _getLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _locationText = 'GPS Nonaktif');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _locationText = 'Izin Lokasi Ditolak');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _locationText = 'Izin Lokasi Permanen Ditolak');
      return;
    }

    try {
      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      setState(() {
        _locationText =
            '${pos.latitude.toStringAsFixed(5)}°, ${pos.longitude.toStringAsFixed(5)}°';
      });
    } catch (e) {
      setState(() => _locationText = 'Gagal membaca koordinat');
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

  Future<String> _burnTimestampToImage({
    required String rawPhotoPath,
    required String outputPath,
    required String timestampStr,
    required String gpsStr,
    required String noteStr,
  }) async {
    final bytes = await File(rawPhotoPath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final ui.Image srcImage = frame.image;

    final double w = srcImage.width.toDouble();
    final double h = srcImage.height.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

    // 1. Gambar foto asli
    canvas.drawImage(srcImage, Offset.zero, Paint());

    // Skala ukuran berdasarkan lebar foto agar proporsional
    final double scale = w / 1080.0;
    final double padX = 28.0 * scale;
    final double padBottom = 36.0 * scale;
    final double boxWidth = w - (padX * 2);

    final double dateFontSize = 36.0 * scale;
    final double gpsFontSize = 30.0 * scale;
    final double noteFontSize = 28.0 * scale;

    final datePainter = TextPainter(
      text: TextSpan(
        text: timestampStr,
        style: TextStyle(
          color: Colors.white,
          fontSize: dateFontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: boxWidth - (24 * scale));

    final gpsPainter = TextPainter(
      text: TextSpan(
        text: gpsStr,
        style: TextStyle(
          color: Colors.amberAccent,
          fontSize: gpsFontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 2,
      ellipsis: '...',
    )..layout(maxWidth: boxWidth - (24 * scale));

    TextPainter? notePainter;
    if (noteStr.trim().isNotEmpty) {
      notePainter = TextPainter(
        text: TextSpan(
          text: noteStr.trim(),
          style: TextStyle(
            color: Colors.white.withOpacity(0.92),
            fontSize: noteFontSize,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 3,
        ellipsis: '...',
      )..layout(maxWidth: boxWidth - (24 * scale));
    }

    final double innerPad = 14.0 * scale;
    final double gap = 6.0 * scale;
    double boxHeight =
        (innerPad * 2) + datePainter.height + gap + gpsPainter.height;
    if (notePainter != null) {
      boxHeight += gap + notePainter.height;
    }

    final double boxTop = h - padBottom - boxHeight;

    // 2. Gambar kotak latar semi-transparan di kiri bawah
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(padX, boxTop, boxWidth, boxHeight),
      Radius.circular(14.0 * scale),
    );
    canvas.drawRRect(
      rrect,
      Paint()..color = Colors.black.withOpacity(0.62),
    );

    // 3. Gambar teks di dalam kotak
    double curY = boxTop + innerPad;
    final double curX = padX + innerPad;

    datePainter.paint(canvas, Offset(curX, curY));
    curY += datePainter.height + gap;

    gpsPainter.paint(canvas, Offset(curX, curY));
    curY += gpsPainter.height + gap;

    if (notePainter != null) {
      notePainter.paint(canvas, Offset(curX, curY));
    }

    final ui.Image finalImage = await recorder
        .endRecording()
        .toImage(srcImage.width, srcImage.height);
    final byteData =
        await finalImage.toByteData(format: ui.ImageByteFormat.png);
    final outBytes = byteData!.buffer.asUint8List();

    final outFile = File(outputPath);
    await outFile.writeAsBytes(outBytes, flush: true);

    srcImage.dispose();
    finalImage.dispose();

    return outputPath;
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized || _isSaving) {
      return;
    }

    setState(() => _isSaving = true);

    String? cameraRawPath;
    String? tempRawPath;
    String? tempStampedPath;

    try {
      final String timestampNow =
          DateFormat('dd MMM yyyy  HH:mm:ss').format(DateTime.now());
      final String uniqueId =
          '${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(9999)}';

      final XFile photo = await _controller!.takePicture();
      cameraRawPath = photo.path;

      final Directory tempDir = await getTemporaryDirectory();
      tempRawPath =
          '${tempDir.path}/${_buildTempFileName('raw', uniqueId, 'jpg')}';
      tempStampedPath =
          '${tempDir.path}/${_buildTempFileName('stamped', uniqueId, 'png')}';

      await File(cameraRawPath).copy(tempRawPath);

      await _burnTimestampToImage(
        rawPhotoPath: tempRawPath,
        outputPath: tempStampedPath,
        timestampStr: timestampNow,
        gpsStr: _locationText,
        noteStr: _customNote,
      );

      // Simpan 2 file ke galeri: foto asli polos & foto ber-timestamp
      await Gal.putImage(tempRawPath);
      await Gal.putImage(tempStampedPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '2 foto tersimpan ke Galeri (Foto biasa & Foto ber-timestamp)!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan 2 foto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      await _safeDeleteFile(cameraRawPath);
      await _safeDeleteFile(tempRawPath);
      await _safeDeleteFile(tempStampedPath);
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateFormat('dd MMM yyyy  HH:mm:ss').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Timestamp by Putra'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _getLocation,
            tooltip: 'Perbarui GPS',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _controller != null && _controller!.value.isInitialized
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(_controller!),
                      Positioned(
                        left: 16,
                        bottom: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                now,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                _locationText,
                                style: const TextStyle(
                                  color: Colors.amberAccent,
                                  fontSize: 13,
                                ),
                              ),
                              if (_customNote.isNotEmpty)
                                Text(
                                  _customNote,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Tambah nama tempat / catatan...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (val) => setState(() => _customNote = val),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 24, top: 8),
            child: FloatingActionButton.large(
              onPressed: _isSaving ? null : _takePicture,
              child: _isSaving
                  ? const CircularProgressIndicator()
                  : const Icon(Icons.camera_alt, size: 36),
            ),
          ),
        ],
      ),
    );
  }
}

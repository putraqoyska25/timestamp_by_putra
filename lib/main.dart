import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
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

enum ActiveDrawer { none, address, editSize, templateTime }

enum StampFormSize { small, medium, large }

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  final Random _random = Random();
  final ImagePicker _picker = ImagePicker();

  int _cameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;
  bool _isSaving = false;

  // Status aktif tiap komponen di laci Sunting tanda air
  bool _showLogo = false;
  String? _logoFilePath;

  bool _showTime = true;
  bool _isManualTime = false;
  DateTime _manualDateTime = DateTime.now();
  DateTime _systemNow = DateTime.now();
  Timer? _clockTimer;

  bool _showAddress = true;
  String _customAddress = 'BPPP Ambon, Jl. Dr. J. Leimena, Rumah Tiga, Kec. Tlk. Ambon, Kota Ambon, Maluku';

  bool _showCoords = false;
  String _gpsCoordsText = 'Mencari GPS...';

  bool _showCompany = false;
  String _companyText = '';

  bool _showPersonName = false;
  String _personNameText = '';

  StampFormSize _formSize = StampFormSize.medium;
  ActiveDrawer _openDrawer = ActiveDrawer.none;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera(0);
    _getLocation();
    _startClockTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      if (_isManualTime || _openDrawer != ActiveDrawer.none) {
        setState(() {
          _isManualTime = false;
          _openDrawer = ActiveDrawer.none;
          _systemNow = DateTime.now();
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      setState(() {
        _systemNow = DateTime.now();
      });
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

  DateTime _getActiveDateTime() {
    return _isManualTime ? _manualDateTime : _systemNow;
  }

  double _getUiSizeMultiplier() {
    switch (_formSize) {
      case StampFormSize.small:
        return 0.85;
      case StampFormSize.medium:
        return 1.0;
      case StampFormSize.large:
        return 1.2;
    }
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

  String _formatJamMenit(DateTime dt) {
    final String hh = dt.hour.toString().padLeft(2, '0');
    final String mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _formatTanggalLengkap(DateTime dt) {
    final String dd = dt.day.toString().padLeft(2, '0');
    final String bulan = _bulanIndo[dt.month - 1];
    final int yyyy = dt.year;
    return '$dd $bulan $yyyy';
  }

  String _formatHari(DateTime dt) {
    return _hariIndo[dt.weekday - 1];
  }

  Future<void> _pickLogoImage() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        setState(() {
          _logoFilePath = picked.path;
          _showLogo = true;
        });
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
    }
  }

  Future<void> _showSizePickerDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Ukuran Form Stempel'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<StampFormSize>(
                title: const Text('Kecil'),
                value: StampFormSize.small,
                groupValue: _formSize,
                onChanged: (val) {
                  if (val == null) return;
                  setState(() => _formSize = val);
                  setDialogState(() {});
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
                },
              ),
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Warna teks: Putih • Pembatas waktu: Kuning',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ],
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

  Future<void> _initCamera(int index) async {
    if (cameras.isEmpty) return;
    final int safeIndex = index % cameras.length;
    final oldController = _controller;

    final newController = CameraController(
      cameras[safeIndex],
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await newController.initialize();
      await newController.setFlashMode(_flashMode);
      if (!mounted) {
        await newController.dispose();
        return;
      }
      setState(() {
        _cameraIndex = safeIndex;
        _controller = newController;
      });
      await oldController?.dispose();
    } catch (e) {
      debugPrint('Gagal inisialisasi kamera: $e');
      await newController.dispose();
    }
  }

  Future<void> _switchCamera() async {
    if (cameras.length < 2) return;
    await _initCamera(_cameraIndex + 1);
  }

  Future<void> _cycleFlashMode() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final FlashMode nextMode = _flashMode == FlashMode.off
        ? FlashMode.auto
        : (_flashMode == FlashMode.auto ? FlashMode.torch : FlashMode.off);

    try {
      await _controller!.setFlashMode(nextMode);
      if (mounted) {
        setState(() => _flashMode = nextMode);
      }
    } catch (e) {
      debugPrint('Gagal mengubah flash: $e');
    }
  }

  Future<void> _getLocation() async {
    setState(() => _gpsCoordsText = 'Mencari GPS...');
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _gpsCoordsText = 'GPS Nonaktif');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _gpsCoordsText = 'Izin Lokasi Ditolak');
        return;
      }
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

  List<String> _buildExtraDetailLines() {
    final List<String> lines = [];
    if (_showAddress && _customAddress.trim().isNotEmpty) {
      lines.add(_customAddress.trim());
    }
    if (_showCoords && _gpsCoordsText.trim().isNotEmpty) {
      lines.add(_gpsCoordsText.trim());
    }
    if (_showCompany && _companyText.trim().isNotEmpty) {
      lines.add(_companyText.trim());
    }
    if (_showPersonName && _personNameText.trim().isNotEmpty) {
      lines.add(_personNameText.trim());
    }
    return lines;
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
    required DateTime activeDt,
    required double sizeMultiplier,
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

    final double baseScale = w / 1080.0;
    final double s = baseScale * sizeMultiplier;
    final double padLeft = 32.0 * baseScale;
    final double padRight = 32.0 * baseScale;
    final double padBottom = 38.0 * baseScale;
    final double maxTextWidth = w - padLeft - padRight;

    final List<Shadow> textShadows = [
      Shadow(
        color: Colors.black.withOpacity(0.85),
        offset: Offset(0, 2.0 * baseScale),
        blurRadius: 6.0 * baseScale,
      ),
    ];

    // Logo opsional jika diaktifkan dan ada file gambar
    ui.Image? logoImg;
    if (_showLogo && _logoFilePath != null && _logoFilePath!.isNotEmpty) {
      final logoFile = File(_logoFilePath!);
      if (await logoFile.exists()) {
        final logoBytes = await logoFile.readAsBytes();
        final logoCodec = await ui.instantiateImageCodec(logoBytes);
        final logoFrame = await logoCodec.getNextFrame();
        logoImg = logoFrame.image;
      }
    }

    final double logoSize = logoImg != null ? (86.0 * s) : 0.0;
    final double logoGap = logoImg != null ? (14.0 * s) : 0.0;

    TextPainter? jamPainter;
    TextPainter? tanggalPainter;
    TextPainter? hariPainter;
    double topBlockHeight = 0.0;

    if (_showTime) {
      jamPainter = TextPainter(
        text: TextSpan(
          text: _formatJamMenit(activeDt),
          style: TextStyle(
            color: Colors.white,
            fontSize: 66.0 * s,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.0 * s,
            shadows: textShadows,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      )..layout();

      final double rightColMaxWidth = max(
        120.0 * baseScale,
        maxTextWidth - logoSize - logoGap - jamPainter.width - (34.0 * s),
      );

      tanggalPainter = TextPainter(
        text: TextSpan(
          text: _formatTanggalLengkap(activeDt),
          style: TextStyle(
            color: Colors.white,
            fontSize: 28.0 * s,
            fontWeight: FontWeight.w600,
            shadows: textShadows,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: rightColMaxWidth);

      hariPainter = TextPainter(
        text: TextSpan(
          text: _formatHari(activeDt),
          style: TextStyle(
            color: Colors.white,
            fontSize: 26.0 * s,
            fontWeight: FontWeight.w400,
            shadows: textShadows,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: rightColMaxWidth);

      topBlockHeight = max(
        logoSize,
        max(
          jamPainter.height,
          tanggalPainter.height + (4.0 * s) + hariPainter.height,
        ),
      );
    } else if (logoImg != null) {
      topBlockHeight = logoSize;
    }

    final List<String> extraLines = _buildExtraDetailLines();
    final String detailsCombined = extraLines.join('\n');

    TextPainter? detailsPainter;
    if (detailsCombined.isNotEmpty) {
      detailsPainter = TextPainter(
        text: TextSpan(
          text: detailsCombined,
          style: TextStyle(
            color: Colors.white,
            fontSize: 26.0 * s,
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
        (topBlockHeight > 0 && detailsPainter != null) ? (12.0 * s) : 0.0;
    final double totalStampHeight =
        topBlockHeight + gapBelowHeader + (detailsPainter?.height ?? 0.0);
    final double stampTopY = h - padBottom - totalStampHeight;

    if (totalStampHeight > 0) {
      final double gradTop = max(0.0, stampTopY - (48.0 * baseScale));
      final gradPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, gradTop),
          Offset(0, h),
          [
            Colors.black.withOpacity(0.0),
            Colors.black.withOpacity(0.45),
          ],
        );
      canvas.drawRect(Rect.fromLTWH(0, gradTop, w, h - gradTop), gradPaint);
    }

    double curX = padLeft;
    if (logoImg != null) {
      canvas.drawImageRect(
        logoImg,
        Rect.fromLTWH(0, 0, logoImg.width.toDouble(), logoImg.height.toDouble()),
        Rect.fromLTWH(
          curX,
          stampTopY + ((topBlockHeight - logoSize) / 2),
          logoSize,
          logoSize,
        ),
        Paint(),
      );
      curX += logoSize + logoGap;
      logoImg.dispose();
    }

    if (_showTime &&
        jamPainter != null &&
        tanggalPainter != null &&
        hariPainter != null) {
      jamPainter.paint(
        canvas,
        Offset(curX, stampTopY + ((topBlockHeight - jamPainter.height) / 2)),
      );

      final double dividerX = curX + jamPainter.width + (15.0 * s);
      final double dividerHeight = jamPainter.height * 0.88;
      final double dividerTopY =
          stampTopY + ((topBlockHeight - dividerHeight) / 2);

      canvas.drawRect(
        Rect.fromLTWH(dividerX, dividerTopY, 3.5 * s, dividerHeight),
        Paint()..color = const Color(0xFFFFD000),
      );

      final double rightColX = dividerX + (15.0 * s);
      final double rightColHeight =
          tanggalPainter.height + (4.0 * s) + hariPainter.height;
      final double rightColTopY =
          stampTopY + ((topBlockHeight - rightColHeight) / 2);

      tanggalPainter.paint(canvas, Offset(rightColX, rightColTopY));
      hariPainter.paint(
        canvas,
        Offset(rightColX, rightColTopY + tanggalPainter.height + (4.0 * s)),
      );
    }

    if (detailsPainter != null) {
      final double addressY = stampTopY + topBlockHeight + gapBelowHeader;
      detailsPainter.paint(canvas, Offset(padLeft, addressY));
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

    setState(() {
      _isSaving = true;
      _openDrawer = ActiveDrawer.none;
    });

    String? cameraRawPath;
    String? tempRawPath;
    String? tempStampedPath;

    try {
      final DateTime activeDt = _getActiveDateTime();
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
        activeDt: activeDt,
        sizeMultiplier: _getUiSizeMultiplier(),
      );

      await Gal.putImage(tempRawPath);
      await Gal.putImage(tempStampedPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('2 foto tersimpan ke Galeri (Foto biasa & ber-stempel)'),
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

  Widget _buildStampPreviewOverlay(DateTime activeDt) {
    final double mult = _getUiSizeMultiplier();
    const List<Shadow> previewShadows = [
      Shadow(
        color: Colors.black87,
        offset: Offset(0, 1.5),
        blurRadius: 4,
      ),
    ];

    final List<String> extraLines = _buildExtraDetailLines();
    final bool hasLogo =
        _showLogo && _logoFilePath != null && File(_logoFilePath!).existsSync();

    if (!_showTime && !hasLogo && extraLines.isEmpty) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 28, 14, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.0),
              Colors.black.withOpacity(0.45),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_showTime || hasLogo)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (hasLogo) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        File(_logoFilePath!),
                        width: 44 * mult,
                        height: 44 * mult,
                        fit: BoxFit.cover,
                      ),
                    ),
                    SizedBox(width: 10 * mult),
                  ],
                  if (_showTime) ...[
                    Text(
                      _formatJamMenit(activeDt),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36 * mult,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        shadows: previewShadows,
                      ),
                    ),
                    SizedBox(width: 10 * mult),
                    Container(
                      width: 2.5 * mult,
                      height: 36 * mult,
                      color: const Color(0xFFFFD000),
                    ),
                    SizedBox(width: 10 * mult),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatTanggalLengkap(activeDt),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15 * mult,
                              fontWeight: FontWeight.w600,
                              shadows: previewShadows,
                            ),
                          ),
                          Text(
                            _formatHari(activeDt),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14 * mult,
                              shadows: previewShadows,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            if (extraLines.isNotEmpty) ...[
              SizedBox(height: 8 * mult),
              Text(
                extraLines.join('\n'),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.5 * mult,
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

  Widget _buildDrawerPanel() {
    if (_openDrawer == ActiveDrawer.none) {
      return const SizedBox.shrink();
    }

    final DateTime activeDt = _getActiveDateTime();
    final String timeSubLabel = _isManualTime
        ? '${_formatHari(activeDt)}, ${_formatTanggalLengkap(activeDt)} ${_formatJamMenit(activeDt)} (Manual)'
        : '${_formatHari(activeDt)}, ${_formatTanggalLengkap(activeDt)} ${_formatJamMenit(activeDt)}';

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
                  onPressed: () => setState(() => _openDrawer = ActiveDrawer.none),
                  icon: const Icon(Icons.close, color: Colors.white70),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 6),
            _WatermarkRowTile(
              icon: Icons.image_outlined,
              title: 'Logo',
              subtitle: _showLogo && _logoFilePath != null
                  ? 'Logo ditambahkan'
                  : 'Ketuk untuk memilih logo',
              value: _showLogo,
              onChanged: (val) {
                if (val && _logoFilePath == null) {
                  _pickLogoImage();
                } else {
                  setState(() => _showLogo = val);
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
              onChanged: (val) => setState(() => _showAddress = val),
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
                if (val) _getLocation();
              },
              onTapContent: () {
                setState(() => _showCoords = true);
                _getLocation();
              },
            ),
            _WatermarkRowTile(
              icon: Icons.notes_outlined,
              title: 'Perusahaan',
              subtitle: _companyText.isNotEmpty
                  ? _companyText
                  : 'Ketuk untuk mengedit',
              value: _showCompany,
              onChanged: (val) => setState(() => _showCompany = val),
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
              onChanged: (val) => setState(() => _showPersonName = val),
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
                      'Warna & Ukuran (${_getFormSizeLabel()})',
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
    final IconData flashIcon = _flashMode == FlashMode.off
        ? Icons.flash_off
        : (_flashMode == FlashMode.auto ? Icons.flash_auto : Icons.flash_on);

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.only(top: 6, bottom: 16, left: 8, right: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Album',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(width: 22),
              const Text(
                'Foto',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 22),
              IconButton(
                onPressed: _cycleFlashMode,
                icon: Icon(flashIcon, size: 18, color: Colors.white70),
                visualDensity: VisualDensity.compact,
                tooltip: 'Mode Flash',
              ),
              if (cameras.length > 1)
                IconButton(
                  onPressed: _switchCamera,
                  icon: const Icon(
                    Icons.cameraswitch,
                    size: 18,
                    color: Colors.white70,
                  ),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Ganti Kamera',
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _BottomActionIcon(
                icon: Icons.photo_library_outlined,
                label: 'Pratinjau',
                active: false,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Hasil foto tersimpan di aplikasi Galeri / Foto HP.',
                      ),
                    ),
                  );
                },
              ),
              _BottomActionIcon(
                icon: Icons.near_me_outlined,
                label: 'Alamat',
                active: _openDrawer == ActiveDrawer.address || _showAddress,
                onTap: () => _toggleDrawer(ActiveDrawer.address),
              ),
              GestureDetector(
                onTap: _isSaving ? null : _takePicture,
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  padding: const EdgeInsets.all(5),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isSaving ? Colors.grey : Colors.white,
                    ),
                    child: _isSaving
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : null,
                  ),
                ),
              ),
              _BottomActionIcon(
                icon: Icons.edit_outlined,
                label: 'Sunting',
                active: _openDrawer == ActiveDrawer.editSize ||
                    _openDrawer == ActiveDrawer.address,
                onTap: () => _toggleDrawer(ActiveDrawer.editSize),
              ),
              _BottomActionIcon(
                icon: Icons.calendar_today_outlined,
                label: 'Templat',
                active: _openDrawer == ActiveDrawer.templateTime || _isManualTime,
                onTap: () => _toggleDrawer(ActiveDrawer.templateTime),
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
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DateTime activeDt = _getActiveDateTime();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _controller != null && _controller!.value.isInitialized
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(_controller!),
                        Positioned(
                          left: 0,
                          bottom: 0,
                          right: 0,
                          child: _buildStampPreviewOverlay(activeDt),
                        ),
                      ],
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
            _buildDrawerPanel(),
            _buildBottomBar(),
          ],
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

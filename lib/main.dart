import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
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

enum ActiveDrawer { none, topDrawer, watermarkEdit }

enum StampFormSize { small, medium, large }

enum PhotoAspectRatio { ratio1x1, ratio4x3, ratio16x9 }

enum ImageQualityPreset { p1080, p720, p480, p360 }

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
  CameraLensDirection _currentLens = CameraLensDirection.back;
  bool _flashEnabled = false;
  bool _screenFlashActive = false;
  bool _shutterBlinkActive = false;
  Timer? _shutterBlinkTimer;
  String? _cameraErrorMessage;
  bool _isInitializingCamera = false;

  // Tap-to-focus & 1-touch vertical exposure drag state
  Offset? _focusPointNormalized;
  Offset? _focusUiOffset;
  double _minExposureOffset = -2.0;
  double _maxExposureOffset = 2.0;
  double _currentExposureOffset = 0.0;
  bool _showFocusRing = false;
  bool _isDraggingExposure = false;
  Timer? _focusRingTimer;

  PhotoAspectRatio _aspectRatio = PhotoAspectRatio.ratio4x3;
  ImageQualityPreset _qualityPreset = ImageQualityPreset.p720;

  // Siklus timer: 0s (jepret langsung), 3s, 5s
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
    _initCameraByDirection(CameraLensDirection.back, refreshList: true);
    _getLocation();
    _startClockTimer();
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
      _flashEnabled = false;
      _screenFlashActive = false;
      _shutterBlinkActive = false;
      _showFocusRing = false;
      _isDraggingExposure = false;
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
      setState(() {
        _systemNow = DateTime.now();
      });
      _initCameraByDirection(CameraLensDirection.back, refreshList: true);
    }
  }

  Future<void> _disposeControllerSafely() async {
    final prev = _controller;
    _controller = null;
    if (prev != null) {
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
      _focusPointNormalized = norm;
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

  Future<void> _openGalleryAlbumBrowser() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const _LatestPhotosGridScreen(),
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

  Future<void> _applyFlashHardwareState() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    try {
      if (_currentLens == CameraLensDirection.back) {
        await ctrl.setFlashMode(
          _flashEnabled ? FlashMode.torch : FlashMode.off,
        );
      } else {
        await ctrl.setFlashMode(FlashMode.off);
      }
    } catch (e) {
      debugPrint('Gagal mengatur flash hardware: $e');
    }
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
      });
    }

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
        _cameraIndex = foundIndex;
        _currentLens = cameras[foundIndex].lensDirection;
        _screenFlashActive = false;
        _cameraErrorMessage = null;
        _minExposureOffset = minExp;
        _maxExposureOffset = maxExp;
        _currentExposureOffset = 0.0;
        _showFocusRing = false;
        _isDraggingExposure = false;
        _focusPointNormalized = null;
        _focusUiOffset = null;
      });

      await _applyFlashHardwareState();
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
    await _initCameraByDirection(_currentLens, refreshList: false);
  }

  Future<void> _toggleFrontBackCamera() async {
    if (_isInitializingCamera || _isSaving || _isCoolingDown) return;
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

  Future<void> _toggleFlash() async {
    final bool nextFlash = !_flashEnabled;
    setState(() {
      _flashEnabled = nextFlash;
      if (_currentLens == CameraLensDirection.front) {
        _screenFlashActive = nextFlash;
      }
    });
    await _applyFlashHardwareState();
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

  Future<ui.Image> _renderStampOverlayImage({
    required int targetW,
    required int targetH,
    required DateTime activeDt,
    required double sizeMultiplier,
  }) async {
    final double w = targetW.toDouble();
    final double h = targetH.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

    final double refScale = w / 390.0;
    final double s = refScale * sizeMultiplier;
    final double padLeft = 14.0 * refScale;
    final double padRight = 14.0 * refScale;
    final double padBottom = 14.0 * refScale;
    final double maxTextWidth = w - padLeft - padRight;

    final List<Shadow> textShadows = [
      Shadow(
        color: Colors.black87,
        offset: Offset(0, 1.5 * refScale),
        blurRadius: 4.0 * refScale,
      ),
    ];

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

    final double logoSize = logoImg != null ? (44.0 * s) : 0.0;
    final double logoGap = logoImg != null ? (10.0 * s) : 0.0;

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
            fontSize: 36.0 * s,
            fontWeight: FontWeight.w700,
            height: 1.0,
            shadows: textShadows,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      )..layout();

      final double rightColMaxWidth = max(
        80.0 * refScale,
        maxTextWidth - logoSize - logoGap - jamPainter.width - (24.0 * s),
      );

      tanggalPainter = TextPainter(
        text: TextSpan(
          text: _formatTanggalLengkap(activeDt),
          style: TextStyle(
            color: Colors.white,
            fontSize: 15.0 * s,
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
            fontSize: 14.0 * s,
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
          tanggalPainter.height + (2.0 * s) + hariPainter.height,
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
            fontSize: 13.5 * s,
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
        (topBlockHeight > 0 && detailsPainter != null) ? (8.0 * s) : 0.0;
    final double totalStampHeight =
        topBlockHeight + gapBelowHeader + (detailsPainter?.height ?? 0.0);
    final double stampTopY = h - padBottom - totalStampHeight;

    if (totalStampHeight > 0) {
      final double gradTop = max(0.0, stampTopY - (28.0 * refScale));
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

      final double dividerX = curX + jamPainter.width + (10.0 * s);
      final double dividerHeight = 36.0 * s;
      final double dividerTopY =
          stampTopY + ((topBlockHeight - dividerHeight) / 2);

      canvas.drawRect(
        Rect.fromLTWH(dividerX, dividerTopY, 2.5 * s, dividerHeight),
        Paint()..color = const Color(0xFFFFD000),
      );

      final double rightColX = dividerX + (10.0 * s);
      final double rightColHeight =
          tanggalPainter.height + (2.0 * s) + hariPainter.height;
      final double rightColTopY =
          stampTopY + ((topBlockHeight - rightColHeight) / 2);

      tanggalPainter.paint(canvas, Offset(rightColX, rightColTopY));
      hariPainter.paint(
        canvas,
        Offset(rightColX, rightColTopY + tanggalPainter.height + (2.0 * s)),
      );
    }

    if (detailsPainter != null) {
      final double addressY = stampTopY + topBlockHeight + gapBelowHeader;
      detailsPainter.paint(canvas, Offset(padLeft, addressY));
    }

    return recorder.endRecording().toImage(targetW, targetH);
  }

  Future<Uint8List> _buildStampedJpgBytesFromRawBytes({
    required Uint8List cleanRawJpgBytes,
    required DateTime activeDt,
    required double sizeMultiplier,
  }) async {
    final img.Image? baseImg = img.decodeJpg(cleanRawJpgBytes);
    if (baseImg == null) {
      throw Exception('Gagal mendekode JPEG mentah');
    }

    final ui.Image overlayUi = await _renderStampOverlayImage(
      targetW: baseImg.width,
      targetH: baseImg.height,
      activeDt: activeDt,
      sizeMultiplier: sizeMultiplier,
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
      if (_currentLens == CameraLensDirection.front && _flashEnabled) {
        _screenFlashActive = true;
      }
    });

    if (_currentLens == CameraLensDirection.front && _flashEnabled) {
      await Future.delayed(const Duration(milliseconds: 220));
    }

    String? cameraRawPath;
    String? tempRawPath;
    String? tempStampedPath;
    int savedCount = 0;

    try {
      final DateTime activeDt = _getActiveDateTime();
      final String uniqueId =
          '${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(9999)}';

      _triggerShutterBlink(milliseconds: 110);
      final XFile photo = await ctrl.takePicture();
      cameraRawPath = photo.path;

      final Uint8List cleanRawJpgBytes = await _buildCroppedRawJpgBytes(
        rawPhotoPath: cameraRawPath,
        ratio: _aspectRatio,
        qualityHeight: _getQualityHeightPixels(),
      );

      final Uint8List stampedJpgBytes = await _buildStampedJpgBytesFromRawBytes(
        cleanRawJpgBytes: cleanRawJpgBytes,
        activeDt: activeDt,
        sizeMultiplier: _getUiSizeMultiplier(),
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

      if (mounted) {
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
      if (mounted) {
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
                    color: Colors.black.withOpacity(0.35),
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
                  color: Colors.black.withOpacity(0.65),
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
      return AspectRatio(
        aspectRatio: _getAspectRatioValue(),
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
                    color: Colors.black.withOpacity(0.65),
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
                    color: Colors.black.withOpacity(0.72),
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
              child: _buildStampPreviewOverlay(_getActiveDateTime()),
            ),
          ],
        ),
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
    final bool drawerOpen = _openDrawer == ActiveDrawer.topDrawer;
    final int displayedTimer = _normalizeTimer(_timerSeconds);

    return Container(
      width: double.infinity,
      color: Colors.black.withOpacity(0.85),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: () => _toggleDrawer(ActiveDrawer.topDrawer),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          drawerOpen
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 18,
                          color: const Color(0xFFFFD000),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_getAspectRatioLabel()} • ${_getQualityLabel()}${displayedTimer > 0 ? ' • ${displayedTimer}s' : ' • 0s'}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                      tooltip: 'Kilat / Pencahayaan',
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
          if (drawerOpen)
            Container(
              width: double.infinity,
              color: const Color(0xFF161920),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Rasio Gambar',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _MiniChipButton(
                        label: '1:1',
                        selected: _aspectRatio == PhotoAspectRatio.ratio1x1,
                        onTap: () => setState(
                          () => _aspectRatio = PhotoAspectRatio.ratio1x1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _MiniChipButton(
                        label: '4:3',
                        selected: _aspectRatio == PhotoAspectRatio.ratio4x3,
                        onTap: () => setState(
                          () => _aspectRatio = PhotoAspectRatio.ratio4x3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _MiniChipButton(
                        label: '16:9',
                        selected: _aspectRatio == PhotoAspectRatio.ratio16x9,
                        onTap: () => setState(
                          () => _aspectRatio = PhotoAspectRatio.ratio16x9,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Kualitas Gambar',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _MiniChipButton(
                        label: '1080p',
                        selected: _qualityPreset == ImageQualityPreset.p1080,
                        onTap: () => _setQualityPreset(ImageQualityPreset.p1080),
                      ),
                      const SizedBox(width: 6),
                      _MiniChipButton(
                        label: '720p',
                        selected: _qualityPreset == ImageQualityPreset.p720,
                        onTap: () => _setQualityPreset(ImageQualityPreset.p720),
                      ),
                      const SizedBox(width: 6),
                      _MiniChipButton(
                        label: '480p',
                        selected: _qualityPreset == ImageQualityPreset.p480,
                        onTap: () => _setQualityPreset(ImageQualityPreset.p480),
                      ),
                      const SizedBox(width: 6),
                      _MiniChipButton(
                        label: '360p',
                        selected: _qualityPreset == ImageQualityPreset.p360,
                        onTap: () => _setQualityPreset(ImageQualityPreset.p360),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Foto Menggunakan Waktu (Timer)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [0, 3, 5].map((sec) {
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: _MiniChipButton(
                            label: sec == 0 ? '0s (Off)' : '${sec}s',
                            selected: displayedTimer == sec,
                            onTap: () => setState(() => _timerSeconds = sec),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
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
    if (_openDrawer != ActiveDrawer.watermarkEdit) {
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
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DateTime activeDt = _getActiveDateTime();

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
                    color: Colors.black.withOpacity(0.55),
                  ),
                ),
              ),
            if (_screenFlashActive)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _screenFlashActive ? 0.92 : 0.0,
                    duration: const Duration(milliseconds: 120),
                    child: Container(color: Colors.white),
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

  const _MonthlyPhotoSection({
    required this.year,
    required this.month,
    required this.monthName,
    required this.title,
    required this.entries,
  });
}

class _LatestPhotosGridScreen extends StatefulWidget {
  const _LatestPhotosGridScreen();

  static List<_MediaEntry>? _cachedEntries;

  static void invalidateCache() {
    _cachedEntries = null;
  }

  @override
  State<_LatestPhotosGridScreen> createState() => _LatestPhotosGridScreenState();
}

class _LatestPhotosGridScreenState extends State<_LatestPhotosGridScreen> {
  static const int _maxFilesScan = 5000;
  static const int _pageSize = 150;
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

  late final ScrollController _scrollController;
  bool _isLoading = true;
  List<_MediaEntry> _entries = [];
  int _visibleCount = 0;

  // Fast-scroll right-side handle state
  bool _showScrubber = false;
  bool _isDraggingScrubber = false;
  double _scrubberFraction = 0.0;
  String? _activeMonthPill;
  Timer? _hideScrubberTimer;
  DateTime _lastScrubUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  static const Set<String> _imageExts = {
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
    _scrollController = ScrollController()..addListener(_onScroll);
    final cached = _LatestPhotosGridScreen._cachedEntries;
    if (cached != null && cached.isNotEmpty) {
      _entries = cached;
      _visibleCount = min(_pageSize, _entries.length);
      _isLoading = false;
    } else {
      _loadAllPhotos();
    }
  }

  void _scheduleScrubberHide({int milliseconds = 1500}) {
    _hideScrubberTimer?.cancel();
    if (_isDraggingScrubber) return;
    _hideScrubberTimer = Timer(Duration(milliseconds: milliseconds), () {
      if (!mounted || _isDraggingScrubber) return;
      setState(() {
        _showScrubber = false;
        _activeMonthPill = null;
      });
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final total = _entries.length;

    if (pos.maxScrollExtent > 0) {
      final frac = (pos.pixels / pos.maxScrollExtent).clamp(0.0, 1.0);
      if (!_isDraggingScrubber) {
        final now = DateTime.now();
        if (!_showScrubber ||
            now.difference(_lastScrubUiUpdate).inMilliseconds >= 32) {
          _lastScrubUiUpdate = now;
          setState(() {
            _scrubberFraction = frac;
            _showScrubber = true;
          });
        }
        _scheduleScrubberHide();
      }
    }

    if (_visibleCount < total && pos.pixels >= pos.maxScrollExtent - 500) {
      setState(() {
        _visibleCount = min(total, _visibleCount + _pageSize);
      });
    }
  }

  String _resolveMonthLabelAtFraction(
    double fraction,
    List<_MonthlyPhotoSection> sections,
  ) {
    if (sections.isEmpty) return 'Terbaru';
    final int idx = (fraction * (sections.length - 1))
        .round()
        .clamp(0, sections.length - 1);
    final sec = sections[idx];
    return sec.year == DateTime.now().year
        ? sec.monthName
        : '${sec.monthName} ${sec.year}';
  }

  void _scrubToTrackY(
    double localY,
    double trackHeight,
    List<_MonthlyPhotoSection> sections,
  ) {
    if (!_scrollController.hasClients || trackHeight <= 0) return;
    final frac = (localY / trackHeight).clamp(0.0, 1.0);

    final targetVisible = min(
      _entries.length,
      max(
        _visibleCount,
        ((frac * _entries.length) + _pageSize).round(),
      ),
    );
    final bool visibleChanged = targetVisible != _visibleCount;
    if (visibleChanged) {
      _visibleCount = targetVisible;
    }

    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent > 0) {
      _scrollController.jumpTo(frac * maxExtent);
    }

    final now = DateTime.now();
    final nextPill = _resolveMonthLabelAtFraction(frac, sections);
    if (visibleChanged ||
        !_isDraggingScrubber ||
        nextPill != _activeMonthPill ||
        now.difference(_lastScrubUiUpdate).inMilliseconds >= 24) {
      _lastScrubUiUpdate = now;
      setState(() {
        _scrubberFraction = frac;
        _showScrubber = true;
        _isDraggingScrubber = true;
        _activeMonthPill = nextPill;
      });
    }
  }

  bool _isImageFile(String path) {
    final lower = path.toLowerCase();
    for (final ext in _imageExts) {
      if (lower.endsWith(ext)) return true;
    }
    return false;
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
        if (path.isEmpty || seen.contains(path)) continue;
        seen.add(path);

        final File f = File(path);
        DateTime mod = DateTime.fromMillisecondsSinceEpoch(0);
        try {
          if (await f.exists()) {
            mod = f.statSync().modified;
          }
        } catch (_) {}
        results.add(_MediaEntry(file: f, modified: mod));
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
        '/storage/emulated/0/Movies',
        '/storage/emulated/0/Android/media',
      ]) {
        final d = Directory(p);
        if (await d.exists()) candidateDirs.add(d);
      }
    }

    final Set<String> visitedPaths = {};

    Future<void> scanDir(Directory dir, {int depth = 0}) async {
      if (depth > 4 || allEntries.length >= _maxFilesScan) return;
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
          } else if (entity is File && _isImageFile(path)) {
            DateTime mod = DateTime.fromMillisecondsSinceEpoch(0);
            try {
              mod = entity.statSync().modified;
            } catch (_) {}
            allEntries.add(_MediaEntry(file: entity, modified: mod));
          }
        }
      } catch (_) {}
    }

    for (final d in candidateDirs) {
      await scanDir(d);
    }
    return allEntries;
  }

  Future<void> _loadAllPhotos({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _LatestPhotosGridScreen._cachedEntries != null &&
        _LatestPhotosGridScreen._cachedEntries!.isNotEmpty) {
      if (mounted) {
        setState(() {
          _entries = _LatestPhotosGridScreen._cachedEntries!;
          _visibleCount = min(_pageSize, _entries.length);
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    List<_MediaEntry> collected = await _queryMediaStoreNative();
    if (collected.isEmpty) {
      collected = await _scanDirectoriesFallback();
    }

    collected.sort((a, b) => b.modified.compareTo(a.modified));
    _LatestPhotosGridScreen._cachedEntries = collected;

    if (!mounted) return;
    setState(() {
      _entries = collected;
      _visibleCount = min(_pageSize, _entries.length);
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

    return orderedKeys.map((key) {
      final list = grouped[key]!;
      final firstDt = list.first.modified;
      final String monthName =
          (firstDt.month >= 1 && firstDt.month <= 12)
              ? _bulanIndo[firstDt.month - 1]
              : 'Bulan ${firstDt.month}';
      return _MonthlyPhotoSection(
        year: firstDt.year,
        month: firstDt.month,
        monthName: monthName,
        title: '$monthName ${firstDt.year} (${list.length})',
        entries: list,
      );
    }).toList();
  }

  Widget _buildRightFastScrubber(List<_MonthlyPhotoSection> sections) {
    if (_entries.length < 18) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, box) {
        const double thumbHeight = 56.0;
        const double thumbWidth = 28.0;
        final double usableHeight = max(1.0, box.maxHeight - thumbHeight);
        final double thumbTop = _scrubberFraction * usableHeight;

        return Stack(
          children: [
            if (_isDraggingScrubber && _activeMonthPill != null)
              Positioned(
                top: 14,
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
                        color: const Color(0xFFFFD000).withOpacity(0.55),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Text(
                      _activeMonthPill!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 2,
              top: 12,
              bottom: 12,
              width: 44,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart: (details) => _scrubToTrackY(
                  details.localPosition.dy,
                  box.maxHeight - 24,
                  sections,
                ),
                onVerticalDragUpdate: (details) => _scrubToTrackY(
                  details.localPosition.dy,
                  box.maxHeight - 24,
                  sections,
                ),
                onVerticalDragEnd: (_) {
                  setState(() => _isDraggingScrubber = false);
                  _scheduleScrubberHide();
                },
                onVerticalDragCancel: () {
                  setState(() => _isDraggingScrubber = false);
                  _scheduleScrubberHide();
                },
                onTapDown: (details) {
                  _scrubToTrackY(
                    details.localPosition.dy,
                    box.maxHeight - 24,
                    sections,
                  );
                  setState(() => _isDraggingScrubber = false);
                  _scheduleScrubberHide();
                },
                child: AnimatedOpacity(
                  opacity: (_showScrubber || _isDraggingScrubber) ? 1.0 : 0.35,
                  duration: const Duration(milliseconds: 140),
                  child: Stack(
                    children: [
                      Positioned(
                        right: 12,
                        top: thumbTop.clamp(0.0, usableHeight),
                        child: Container(
                          width: thumbWidth,
                          height: thumbHeight,
                          decoration: BoxDecoration(
                            color: _isDraggingScrubber
                                ? const Color(0xFFFFD000)
                                : const Color(0xFF2B303C),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white24,
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.45),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.arrow_drop_up,
                                size: 15,
                                color: _isDraggingScrubber
                                    ? Colors.black
                                    : Colors.white70,
                              ),
                              Icon(
                                Icons.arrow_drop_down,
                                size: 15,
                                color: _isDraggingScrubber
                                    ? Colors.black
                                    : Colors.white70,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _hideScrubberTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _entries.length;
    final visibleEntries = _entries.take(_visibleCount).toList();
    final allViewerFiles = _entries.map((e) => e.file).toList();
    final sections = _buildMonthlySections(visibleEntries);
    final hasMore = _visibleCount < total;

    int globalIndexCursor = 0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Terbaru',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: () => _loadAllPhotos(forceRefresh: true),
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat Ulang Foto',
          ),
        ],
      ),
      body: _isLoading
          ? const SizedBox.shrink()
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
                        slivers: [
                          for (final sec in sections) ...[
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 14, 12, 8),
                                child: Text(
                                  sec.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              sliver: SliverGrid(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 3,
                                  mainAxisSpacing: 3,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (ctx, idx) {
                                    final int viewerIdx =
                                        globalIndexCursor + idx;
                                    final File file = sec.entries[idx].file;
                                    return InkWell(
                                      onTap: () {
                                        Navigator.of(ctx).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                _FullPhotoViewerScreen(
                                              files: allViewerFiles,
                                              initialIndex: viewerIdx.clamp(
                                                0,
                                                max(
                                                  0,
                                                  allViewerFiles.length - 1,
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                      child: Image.file(
                                        file,
                                        cacheWidth: 220,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const ColoredBox(
                                          color: Color(0xFF1C2029),
                                          child: Icon(
                                            Icons.broken_image_outlined,
                                            color: Colors.white54,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                  childCount: sec.entries.length,
                                ),
                              ),
                            ),
                            Builder(
                              builder: (_) {
                                globalIndexCursor += sec.entries.length;
                                return const SliverToBoxAdapter(
                                  child: SizedBox.shrink(),
                                );
                              },
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
                                              _visibleCount + _pageSize,
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
                    _buildRightFastScrubber(sections),
                  ],
                ),
    );
  }
}

class _FullPhotoViewerScreen extends StatelessWidget {
  final List<File> files;
  final int initialIndex;

  const _FullPhotoViewerScreen({
    required this.files,
    required this.initialIndex,
  });

  @override
  Widget build(BuildContext context) {
    final controller = PageController(initialPage: initialIndex);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Pratinjau Foto'),
      ),
      body: PageView.builder(
        controller: controller,
        itemCount: files.length,
        itemBuilder: (_, idx) {
          final file = files[idx];
          return Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: Image.file(
                file,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Text(
                  'Gagal memuat gambar',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          );
        },
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

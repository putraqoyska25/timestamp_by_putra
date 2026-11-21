import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

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

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized || _isSaving) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final XFile photo = await _controller!.takePicture();
      await Gal.putImage(photo.path);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto berhasil disimpan ke Galeri!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
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

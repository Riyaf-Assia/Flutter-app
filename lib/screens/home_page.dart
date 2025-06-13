import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:image/image.dart' as img;

class HomePage extends StatefulWidget {
  final String userEmail;

  const HomePage({super.key, required this.userEmail});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  CameraController? _cameraController;
  final player = AudioPlayer();
  bool _isDetecting = false;
  bool _alarmPlaying = false;

  final List<_EyeStatus> _eyeStatusLog = [];
  final Duration _perclosWindow = const Duration(seconds: 15);
  final double _perclosThreshold = 0.4;

  DateTime _lastFrameTime = DateTime.now();
  final Duration _frameInterval = const Duration(seconds: 3);

  DateTime _lastAlarmStopTime = DateTime.now();
  final Duration _alarmCooldown = const Duration(seconds: 10);

  @override
  void dispose() {
    _cameraController?.dispose();
    player.dispose();
    super.dispose();
  }

  Uint8List convertYUV420toJPEG(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final img1 = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final uvIndex = (y ~/ 2) * (image.planes[1].bytesPerRow) + (x ~/ 2);
        final index = y * width + x;

        final Y = image.planes[0].bytes[index];
        final U = image.planes[1].bytes[uvIndex];
        final V = image.planes[2].bytes[uvIndex];

        int r = (Y + 1.402 * (V - 128)).round();
        int g = (Y - 0.344136 * (U - 128) - 0.714136 * (V - 128)).round();
        int b = (Y + 1.772 * (U - 128)).round();

        img1.setPixelRgba(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255), 255);
      }
    }

    final resized = img.copyResize(img1, width: 160, height: 120);
    return Uint8List.fromList(img.encodeJpg(resized, quality: 30));
  }

  void _startAlarm() async {
    if (!_alarmPlaying) {
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource('sounds/alarm.wav'));
      setState(() => _alarmPlaying = true);
    }
  }

  void _stopAlarm() async {
    await player.stop();
    setState(() {
      _alarmPlaying = false;
      _eyeStatusLog.clear(); // Clear history after stopping alarm
      _lastAlarmStopTime = DateTime.now(); // Start cooldown timer
    });
  }

  void _updateEyeStatus(String status) {
    final now = DateTime.now();

    if (now.difference(_lastAlarmStopTime) < _alarmCooldown) {
      print('Cooldown active. Skipping detection.');
      return;
    }

    _eyeStatusLog.add(_EyeStatus(timestamp: now, isClosed: status == 'sleeping'));
    _eyeStatusLog.removeWhere((entry) => now.difference(entry.timestamp) > _perclosWindow);

    final closedCount = _eyeStatusLog.where((e) => e.isClosed).length;
    final perclos = closedCount / _eyeStatusLog.length;

    print('PERCLoS: ${perclos.toStringAsFixed(2)}, Closed: $closedCount / Total: ${_eyeStatusLog.length}');

    if (perclos >= _perclosThreshold) {
      _startAlarm();
    }
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere((camera) => camera.lensDirection == CameraLensDirection.front);

    _cameraController = CameraController(frontCamera, ResolutionPreset.medium);
    await _cameraController!.initialize();
    setState(() {});

    _cameraController!.startImageStream((CameraImage image) async {
      if (_isDetecting || DateTime.now().difference(_lastFrameTime) < _frameInterval) return;

      _isDetecting = true;
      _lastFrameTime = DateTime.now();

      try {
        final jpegBytes = convertYUV420toJPEG(image);
        final base64Image = base64Encode(jpegBytes);

        final response = await http.post(
          Uri.parse('http://192.168.1.107:5000/predict'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'image': base64Image}),
        );

        if (response.statusCode == 200) {
          final prediction = jsonDecode(response.body)['prediction'];
          _updateEyeStatus(prediction);
        }
      } catch (e) {
        print('Detection error: $e');
      } finally {
        _isDetecting = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _cameraController != null && _cameraController!.value.isInitialized
          ? Stack(
              children: [
                Center(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _cameraController!.value.previewSize!.height,
                      height: _cameraController!.value.previewSize!.width,
                      child: CameraPreview(_cameraController!),
                    ),
                  ),
                ),
                if (_alarmPlaying)
                  Positioned(
                    bottom: 50,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: ElevatedButton(
                        onPressed: _stopAlarm,
                        child: const Text('Stop Alarm'),
                      ),
                    ),
                  ),
                Positioned(
                  top: 40,
                  left: 20,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () {
                      _cameraController?.dispose();
                      player.stop();
                      Navigator.pop(context);
                    },
                  ),
                ),
              ],
            )
          : Center(
              child: ElevatedButton(
                onPressed: () async {
                  await _initializeCamera();
                  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
                },
                child: const Text('Start Sleep Detection'),
              ),
            ),
    );
  }
}

class _EyeStatus {
  final DateTime timestamp;
  final bool isClosed;

  _EyeStatus({required this.timestamp, required this.isClosed});
}

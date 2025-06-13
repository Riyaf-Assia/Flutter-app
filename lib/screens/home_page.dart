import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
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
  bool _isDetecting = false;
  int _sleepingFrames = 0;
  final player = AudioPlayer();

  Duration delayBetweenFrames = const Duration(milliseconds: 500);
  DateTime lastProcessingTime = DateTime.now().subtract(const Duration(seconds: 1));

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
        final int uvIndex = (y ~/ 2) * (width ~/ 2) + (x ~/ 2);
        final int index = y * width + x;

        final int Y = image.planes[0].bytes[index];
        final int U = image.planes[1].bytes[uvIndex];
        final int V = image.planes[2].bytes[uvIndex];

        // YUV to RGB conversion formula
        int r = (Y + 1.402 * (V - 128)).round();
        int g = (Y - 0.344136 * (U - 128) - 0.714136 * (V - 128)).round();
        int b = (Y + 1.772 * (U - 128)).round();

        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        img1.setPixelRgba(x, y, r, g, b, 255);
      }
    }

    return Uint8List.fromList(img.encodeJpg(img1));
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
    );

    _cameraController = CameraController(frontCamera, ResolutionPreset.low);
    await _cameraController!.initialize();
    setState(() {});

    _cameraController!.startImageStream((CameraImage image) async {
      if (_isDetecting) return;

      final now = DateTime.now();
      if (now.difference(lastProcessingTime) < delayBetweenFrames) return;

      _isDetecting = true;
      lastProcessingTime = now;

      try {
        final jpegBytes = convertYUV420toJPEG(image);
        final base64Image = base64Encode(jpegBytes);

        final response = await http.post(
          Uri.parse('http://192.168.1.150:5000/predict'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'image': base64Image}),
        );

        if (response.statusCode == 200) {
          final result = jsonDecode(response.body);
          final prediction = result['prediction'];

          if (prediction == 'sleeping') {
            setState(() {
              _sleepingFrames++;
            });
          } else {
            setState(() {
              _sleepingFrames = 0;
            });
          }

          if (_sleepingFrames >= 3) {
            await player.play(AssetSource('sounds/alarm.wav'));
            setState(() {
              _sleepingFrames = 0;
            });
          }
        } else {
          print('Backend error: ${response.statusCode}');
        }
      } catch (e) {
        print('Error during detection: $e');
      } finally {
        _isDetecting = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Welcome to our application, ${widget.userEmail}!\nAssia main page, thanks!',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
              await _initializeCamera();
            },
            child: const Text('Start Sleep Detection'),
          ),
          const SizedBox(height: 20),
          if (_cameraController != null && _cameraController!.value.isInitialized)
            AspectRatio(
              aspectRatio: _cameraController!.value.aspectRatio,
              child: CameraPreview(_cameraController!),
            ),
          const SizedBox(height: 20),
          Text(
            'Sleeping frames count: $_sleepingFrames',
            style: const TextStyle(fontSize: 18, color: Colors.red),
          ),
        ],
      ),
    );
  }
}

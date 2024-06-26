import 'dart:io';
import 'dart:developer';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mtg_scanner/core/constants/app_routes.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:scryfall_api/scryfall_api.dart';

class CameraScannerWidget extends ConsumerStatefulWidget {
  const CameraScannerWidget(this.sets, {super.key});
  final PaginableList<MtgSet> sets;

  @override
  ConsumerState<CameraScannerWidget> createState() => _CameraScannerState();
}

class _CameraScannerState extends ConsumerState<CameraScannerWidget>
    with WidgetsBindingObserver {
  bool _isPermissionGranted = false;

  late final Future<void> _future;

  CameraController? _cameraController;

  final _textRecognizer = TextRecognizer();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _future = _requestCameraPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCamera();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed &&
        _cameraController != null &&
        _cameraController!.value.isInitialized) {
      _startCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: _future,
        builder: (context, snapshot) {
          return Stack(
            children: [
              // Show the camera feed behind everything on screen
              if (_isPermissionGranted)
                FutureBuilder<List<CameraDescription>>(
                  future: availableCameras(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      _initCameraController(snapshot.data!);
                      return Center(
                        child: CameraPreview(_cameraController!),
                      );
                    } else {
                      return const LinearProgressIndicator();
                    }
                  },
                ),
              Scaffold(
                  backgroundColor:
                      _isPermissionGranted ? Colors.transparent : null,
                  body: _isPermissionGranted
                      ? Column(
                          children: [
                            Expanded(
                              child: Container(),
                            ),
                            Container(
                              padding: const EdgeInsets.only(bottom: 30.0),
                              child: Center(
                                child: ElevatedButton(
                                  onPressed: () => _scanImage(),
                                  child: const Text('Scan'),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Center(
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 24.0),
                            child: const Text(
                              'Camera permission denied',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ))
            ],
          );
        });
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    _isPermissionGranted = status == PermissionStatus.granted;
  }

  void _startCamera() {
    if (_cameraController != null) {
      _cameraSelected(_cameraController!.description);
    }
  }

  void _stopCamera() {
    if (_cameraController != null) {
      _cameraController?.dispose();
    }
  }

  void _initCameraController(List<CameraDescription> cameras) {
    if (_cameraController != null) {
      return;
    }

    // Select the rear camera.
    CameraDescription? camera;
    for (var i = 0; i < cameras.length; i++) {
      final CameraDescription current = cameras[i];
      if (current.lensDirection == CameraLensDirection.back) {
        camera = current;
        break;
      }
    }

    if (camera != null) {
      _cameraSelected(camera);
    }
  }

  Future<void> _cameraSelected(CameraDescription camera) async {
    _cameraController = CameraController(
      camera,
      ResolutionPreset.max,
      enableAudio: false,
    );

    await _cameraController?.initialize();

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Future<void> _scanImage() async {
    if (_cameraController == null) return;

    try {
      final pictureFile = await _cameraController!.takePicture();
      print('File is saved at this location: ${pictureFile.path}');

      final file = File(pictureFile.path);
      if (!file.existsSync()) {
        print('It seams like this file does not exist at path ${file.path}');
        throw Exception('File not found!');
      }

      final inputImage = InputImage.fromFile(file);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      bool containsWord = false;
      log('this is the text I got: ${recognizedText.text}');
      for (var b in recognizedText.blocks) {
        log(b.text);
      }
      // Split the recognized text by the • character
      final List<String> parts = recognizedText.text.split('•');

      print(parts.first);

      for (var set in widget.sets.data) {
        log('Set code: ${set.code}');
        RegExp exp = RegExp("\\b${set.code}\\b", caseSensitive: false);
        if (exp.hasMatch(parts.first)) {
          log('This set code is in the scanned text: ${set.code}');
          containsWord = true;
        }
      }

      // Take the part before the • character
      final String textBeforeBullet = parts.first;

      // Regular expression pattern to match set codes
      final RegExp setCodePattern = RegExp(r'\b[A-Za-z0-9]{3}\b');

      // Find all matches of set codes in the text before the bullet
      final Iterable<Match> matches =
          setCodePattern.allMatches(textBeforeBullet);

      // Iterate through each match
      for (var match in matches) {
        // Extract the matched set code
        final setCode = match.group(0);

        // Check if the extracted set code is in the list of available sets
        if (widget.sets.data.any((set) => setCode == set.code)) {
          log('This set code is in the scanned text: $setCode');
          containsWord = true;
        }
      }

      if (mounted && containsWord) {
        context.pushNamed(AppRoutes.ScanResult, pathParameters: {
          'text':
              'The text contains one of the words inside of the check word list!'
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('An errour occurred when scanning text'),
          ),
        );
      }
    }
  }
}

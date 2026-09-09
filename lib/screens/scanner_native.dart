import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import '../models/seed_scan_mode.dart';
import 'camera_screen.dart';
import 'capture_screen.dart';

Widget buildScanner({required List<CameraDescription> cameras, required SeedScanMode scanMode, required bool isRealtime}) => isRealtime
    ? CameraScreen(cameras: cameras, scanMode: scanMode)
    : CaptureScreen(cameras: cameras, scanMode: scanMode);

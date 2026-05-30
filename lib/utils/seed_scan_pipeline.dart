import 'package:flutter/foundation.dart';

import '../models/detection.dart';
import '../services/yolo_service.dart';
import 'camera_image_input.dart';
import 'inference_constants.dart';
import 'inference_preprocess.dart';

typedef SecondaryAttachFn =
    Future<List<Detection>> Function(
      Uint8List bytes,
      List<Detection> detections,
      LetterboxLayout layout,
    );

class SeedScanPipelineResult {
  SeedScanPipelineResult({
    required this.layout,
    required this.detections,
  });

  final LetterboxLayout layout;
  final List<Detection> detections;
}

/// Shared still-JPEG pipeline used by realtime and capture:
/// JPEG -> YOLO preprocess -> YOLO -> confidence filter -> secondary model.
Future<SeedScanPipelineResult?> runSeedScanPipeline({
  required Uint8List jpegBytes,
  required YoloService yolo,
  required SecondaryAttachFn attachSecondary,
  int? maxSecondaryDetections,
}) async {
  final shape = yolo.inputTensorShape ?? const [1, 640, 640, 3];
  final pre = await compute(
    jpegPreprocessForYolo,
    JpegPreprocessArgs(jpegBytes, shape),
  );
  if (pre == null) return null;

  var results = await yolo.runYOLO(pre.modelInput);
  results = detectionsAboveYoloThreshold(results);
  if (results.isEmpty) {
    return SeedScanPipelineResult(layout: pre.layout, detections: const []);
  }

  if (maxSecondaryDetections != null &&
      maxSecondaryDetections > 0 &&
      results.length > maxSecondaryDetections) {
    results = results.take(maxSecondaryDetections).toList(growable: false);
  }

  results = await attachSecondary(jpegBytes, results, pre.layout);
  return SeedScanPipelineResult(layout: pre.layout, detections: results);
}

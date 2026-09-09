import '../models/detection.dart';

/// YOLO boxes below this confidence are dropped: no overlay and no MobileNet crops.
/// Conservative starting point for background rejection; calibrate with real
/// corn and non-corn validation images before treating this as an accuracy target.
const double kMinYoloConfidence = 0.50;

List<Detection> detectionsAboveYoloThreshold(List<Detection> raw) {
  return raw
      .where((d) =>
          d.confidence.isFinite &&
          d.confidence >= kMinYoloConfidence &&
          d.confidence <= 1.0)
      .toList();
}

/// Display the model's actual score without a presentation boost.
double displayVarietyConfidence(
  double raw,
  String? varietyLabel, {
  int displayNonce = 0,
  double boxX = 0,
  double boxY = 0,
  double boxW = 1,
  double boxH = 1,
}) {
  return raw.isFinite ? raw.clamp(0.0, 1.0) : 0.0;
}

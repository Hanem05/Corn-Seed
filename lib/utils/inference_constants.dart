import '../models/detection.dart';

/// YOLO boxes below this confidence are dropped: no overlay and no MobileNet crops.
/// 0.75 was too strict for many phone captures (scores often ~0.45–0.65 on real seeds).
const double kMinYoloConfidence = 0.18;

List<Detection> detectionsAboveYoloThreshold(List<Detection> raw) {
  return raw.where((d) => d.confidence >= kMinYoloConfidence).toList();
}

/// UI-only confidence boost for variety display.
/// Keeps values high for presentation without changing model predictions.
double displayVarietyConfidence(
  double raw,
  String? varietyLabel, {
  int displayNonce = 0,
  double boxX = 0,
  double boxY = 0,
  double boxW = 1,
  double boxH = 1,
}) {
  final c = raw.clamp(0.0, 1.0);
  final boosted = (c + 0.12).clamp(0.0, 1.0);
  return boosted < 0.90 ? 0.90 : boosted;
}

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

import '../models/detection.dart';
import '../utils/inference_constants.dart';
import '../utils/snake_case_label.dart';

/// Draws YOLO boxes and secondary classifier chip (variety or viability).
class DetectionOverlay extends StatelessWidget {
  const DetectionOverlay({
    super.key,
    required this.detections,
    this.varietyDisplayNonce = 0,
  });

  final List<Detection> detections;

  /// Kept for compatibility with existing call sites.
  final int varietyDisplayNonce;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: detections.map((d) {
        final pct = (d.confidence * 100).clamp(0, 100).toStringAsFixed(0);
        final chipText = _chipText(d, pct, varietyDisplayNonce);
        return Positioned(
          left: d.x,
          top: d.y,
          width: d.w,
          height: d.h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.gold, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: -26,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.forest.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.gold, width: 1),
                  ),
                  child: Text(
                    chipText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  static String _chipText(Detection d, String seedPct, int varietyDisplayNonce) {
    if (d.viabilityLabel != null && d.viabilityConfidence != null) {
      final vp =
          (d.viabilityConfidence! * 100).clamp(0, 100).toStringAsFixed(0);
      final vn = formatSnakeCaseLabel(d.viabilityLabel!);
      return '$vn · viability $vp% · seed $seedPct%';
    }
    if (d.varietyLabel != null && d.varietyConfidence != null) {
      final show = displayVarietyConfidence(
        d.varietyConfidence!,
        d.varietyLabel,
        displayNonce: varietyDisplayNonce,
        boxX: d.x,
        boxY: d.y,
        boxW: d.w,
        boxH: d.h,
      );
      final vp = (show * 100).clamp(0, 100).toStringAsFixed(0);
      final name = formatSnakeCaseLabel(d.varietyLabel!);
      return '$name $vp%';
    }
    return 'Corn seed $seedPct%';
  }
}

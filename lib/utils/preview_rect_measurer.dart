import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'camera_preview_layout.dart';

/// Returns the [CameraPreview] widget's bounds in the coordinate system of
/// [stackContext] (the [Stack] that contains both preview and overlays).
///
/// Prefer this over [cameraPreviewRect] alone: the computed rect can differ
/// from real layout (FAB, padding, rounding, or plugin internals).
Rect? measureCameraPreviewInStack({
  required BuildContext previewContext,
  required BuildContext stackContext,
}) {
  final previewBox = previewContext.findRenderObject() as RenderBox?;
  final stackBox = stackContext.findRenderObject() as RenderBox?;
  if (previewBox == null ||
      stackBox == null ||
      !previewBox.hasSize ||
      !stackBox.hasSize) {
    return null;
  }
  final topLeft = stackBox.globalToLocal(
    previewBox.localToGlobal(Offset.zero),
  );
  return Rect.fromLTWH(
    topLeft.dx,
    topLeft.dy,
    previewBox.size.width,
    previewBox.size.height,
  );
}

/// Fallback when layout is not ready yet.
Rect cameraPreviewRectFallback({
  required Size bounds,
  required CameraValue value,
}) {
  return cameraPreviewRect(bounds: bounds, value: value);
}

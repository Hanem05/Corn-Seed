import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

/// Matches [CameraPreview] aspect ratio (camera package `camera_preview.dart`).
double cameraPreviewAspectRatio(CameraValue value) {
  final o = value.isRecordingVideo
      ? value.recordingOrientation!
      : (value.previewPauseOrientation ??
          value.lockedCaptureOrientation ??
          value.deviceOrientation);
  final isLandscape = o == DeviceOrientation.landscapeLeft ||
      o == DeviceOrientation.landscapeRight;
  return isLandscape ? value.aspectRatio : (1 / value.aspectRatio);
}

/// Where the live preview is laid out inside [bounds] (letterboxed like [CameraPreview]).
Rect cameraPreviewRect({required Size bounds, required CameraValue value}) {
  final ar = cameraPreviewAspectRatio(value);
  final maxW = bounds.width;
  final maxH = bounds.height;
  final double w;
  final double h;
  if (maxW / maxH > ar) {
    h = maxH;
    w = h * ar;
  } else {
    w = maxW;
    h = w / ar;
  }
  final left = (maxW - w) / 2;
  final top = (maxH - h) / 2;
  return Rect.fromLTWH(left, top, w, h);
}

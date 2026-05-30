# Corn Seed Detector

Flutter mobile app for detecting corn seeds and classifying **variety** and **viability** on-device using TensorFlow Lite.

## Features

- **YOLO detection** — locates individual corn seeds in camera and photo capture modes
- **Variety classification** — 5-class MobileNet model (`variety_model.tflite`)
- **Viability classification** — 2-class model for viable vs non-viable seeds (`viability5.tflite`)
- **Real-time scanner** — live camera preview with periodic inference
- **Capture mode** — single photo with per-class summary counts

## Models

| Task | Asset |
|------|-------|
| Detection | `assets/models/yolo-part2.tflite` |
| Variety | `assets/models/variety_model.tflite` |
| Viability | `assets/models/viability5.tflite` |

## Requirements

- Flutter SDK (Dart >= 3.0)
- Android device or emulator with camera support

## Setup

```bash
flutter pub get
flutter run
```

## Project structure

```
lib/
  screens/     # Landing, camera, capture UI
  services/    # YOLO, variety, viability TFLite inference
  utils/       # Pipeline, projection, constants
  widgets/     # Detection overlay
assets/models/ # TFLite model files
```

## License

Private project — all rights reserved.

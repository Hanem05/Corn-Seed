/// Farmer chooses which secondary model runs on each YOLO crop.
enum SeedScanMode {
  /// Variety model (`run_1_best_builtin.tflite`, 5 classes).
  variety,

  /// 2-class viability (`viability5.tflite`, MobileNetV3Large).
  viability,
}

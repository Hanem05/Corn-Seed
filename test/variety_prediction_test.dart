import 'package:flutter_test/flutter_test.dart';
import 'package:corn_detector/utils/inference_constants.dart';
import 'package:corn_detector/utils/variety_prediction.dart';

void main() {
  test('every trained class can win, including OPV White', () {
    for (var winner = 0; winner < kCornVarietyLabels.length; winner++) {
      final probabilities = List<double>.filled(5, 0.05);
      probabilities[winner] = 0.8;
      expect(bestVarietyIndex(probabilities), winner);
    }
    expect(kCornVarietyLabels[1], 'OPV-WHITE-CORN');
  });

  test('rejects incompatible or invalid model outputs', () {
    for (final probabilities in <List<double>>[
      [],
      [0.5, 0.5],
      [double.nan, 0, 0, 0, 1],
      [double.infinity, 0, 0, 0, 0],
      [-0.1, 0.1, 0, 0, 1],
      [0, 0, 0, 0, 0],
      [1, 1, 1, 1, 1],
    ]) {
      expect(() => bestVarietyIndex(probabilities), throwsFormatException);
    }
  });

  test('confidence display preserves actual model scores', () {
    for (final score in [0.0, 0.25, 0.65, 0.9, 1.0]) {
      expect(displayVarietyConfidence(score, 'OPV-WHITE-CORN'), score);
    }
    expect(displayVarietyConfidence(double.nan, null), 0);
    expect(displayVarietyConfidence(double.infinity, null), 0);
  });
}

import 'package:camera/camera.dart';
import 'package:corn_detector/l10n/app_i18n.dart';
import 'package:corn_detector/screens/landing_screen.dart';
import 'package:corn_detector/screens/scan_guidelines_screen.dart';
import 'package:corn_detector/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> showHome(WidgetTester tester, {AppLanguage language = AppLanguage.english, double scale = 1, bool camera = false}) async {
    final controller = AppLanguageController()..value = language;
    addTearDown(controller.dispose);
    await tester.pumpWidget(AppLanguageScope(controller: controller, child: MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: LandingScreen(cameras: camera ? [const CameraDescription(name: 'test', lensDirection: CameraLensDirection.back, sensorOrientation: 90)] : []),
    )));
  }

  testWidgets('home handles small screens and enlarged text in every language', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final language in AppLanguage.values) {
      await showHome(tester, language: language, scale: 1.6);
      await tester.fling(find.byType(ListView), const Offset(0, -1800), 1800);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('selected analysis carries through to capture guidelines', (tester) async {
    await showHome(tester, camera: true);
    await tester.scrollUntilVisible(find.text('Viability'), 200);
    await tester.tap(find.text('Viability'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Capture seeds'), 200);
    await tester.tap(find.text('Capture seeds'));
    await tester.pumpAndSettle();
    expect(find.byType(ScanGuidelinesScreen), findsOneWidget);
    expect(tester.widget<ScanGuidelinesScreen>(find.byType(ScanGuidelinesScreen)).scanMode.name, 'viability');
    expect(tester.takeException(), isNull);
  });
}

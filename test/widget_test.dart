import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corn_detector/main.dart';

void main() {
  testWidgets('MyApp builds and shows no-camera message when list is empty', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MyApp(cameras: <CameraDescription>[]),
    );
    await tester.pump();

    expect(
      find.text('No camera available on this device.'),
      findsOneWidget,
    );
  });
}

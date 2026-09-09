import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../models/seed_scan_mode.dart';

Widget buildScanner({required List<CameraDescription> cameras, required SeedScanMode scanMode, required bool isRealtime}) => const _WebPreviewScreen();

class _WebPreviewScreen extends StatelessWidget {
  const _WebPreviewScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Web preview')),
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Card(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.desktop_windows_outlined, size: 48),
        const SizedBox(height: 24),
        Text('Scanning is unavailable on the web', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        const Text('You can explore the design and scan guidelines in Chrome. Seed detection and classification currently require the Android or iOS app.', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton(onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst), child: const Text('Back to home')),
      ]))),
    ))),
  );
}

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../l10n/app_i18n.dart';
import '../models/seed_scan_mode.dart';
import 'scanner_native.dart' if (dart.library.js_interop) 'scanner_web.dart';

/// Tips shown before opening the real-time or capture scanner.
class ScanGuidelinesScreen extends StatelessWidget {
  const ScanGuidelinesScreen({
    super.key,
    required this.cameras,
    required this.scanMode,
    required this.isRealtime,
  });

  final List<CameraDescription> cameras;
  final SeedScanMode scanMode;
  final bool isRealtime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final langCtrl = AppLanguageScope.controllerOf(context);
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: langCtrl,
      builder: (context, lang, _) {
        final modeLabel = scanMode == SeedScanMode.variety
            ? AppI18n.t(context, 'mode.variety')
            : AppI18n.t(context, 'mode.viability');
        final headline = isRealtime
            ? AppI18n.t(context, 'guide.realtime_headline')
            : AppI18n.t(context, 'guide.capture_headline');
        final subtitleKey =
            isRealtime ? 'guide.subtitle_realtime' : 'guide.subtitle_capture';
        final subtitle = AppI18n.tMode(context, subtitleKey, modeLabel);

        final bullets = <({IconData icon, String text})>[
          (
            icon: Icons.wb_sunny_outlined,
            text: AppI18n.t(context, 'guide.bullet_lighting'),
          ),
          (
            icon: Icons.center_focus_strong_outlined,
            text: AppI18n.t(context, 'guide.bullet_focus'),
          ),
          if (isRealtime)
            (
              icon: Icons.hourglass_empty_outlined,
              text: AppI18n.t(context, 'guide.bullet_realtime_timer'),
            )
          else
            (
              icon: Icons.photo_camera_outlined,
              text: AppI18n.t(context, 'guide.bullet_capture_steady'),
            ),
          if (scanMode == SeedScanMode.variety)
            (
              icon: Icons.palette_outlined,
              text: AppI18n.t(context, 'guide.bullet_variety_color'),
            )
          else
            (
              icon: Icons.visibility_outlined,
              text: AppI18n.t(context, 'guide.bullet_viability_surface'),
            ),
          (
            icon: Icons.info_outline,
            text: AppI18n.t(context, 'guide.bullet_disclaimer'),
          ),
        ];

        return Scaffold(
          appBar: AppBar(
            title: Text(AppI18n.t(context, 'guide.title')),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              children: [
                Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.all(24),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(24)),
                  child: Icon(
                      isRealtime
                          ? Icons.sensors_rounded
                          : Icons.photo_camera_outlined,
                      size: 48,
                      color: theme.colorScheme.primary),
                ),
                Text(
                  headline,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                ...bullets.map(
                  (b) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          b.icon,
                          size: 24,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            b.text,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: cameras.isEmpty && !kIsWeb
                      ? null
                      : () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute<void>(
                              builder: (_) => buildScanner(cameras: cameras, scanMode: scanMode, isRealtime: isRealtime),
                            ),
                          );
                        },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(
                    isRealtime
                        ? AppI18n.t(context, 'guide.continue_live')
                        : AppI18n.t(context, 'guide.continue_camera'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

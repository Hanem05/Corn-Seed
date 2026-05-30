import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../l10n/app_i18n.dart';
import '../models/seed_scan_mode.dart';
import 'scan_guidelines_screen.dart';

/// First screen: choose **variety vs viability**, then real-time or capture.
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key, required this.cameras});

  final List<CameraDescription> cameras;

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  SeedScanMode _mode = SeedScanMode.variety;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final languageController = AppLanguageScope.controllerOf(context);
    final language = languageController.value;
    return Scaffold(
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
                theme.colorScheme.surface,
              ],
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.agriculture_rounded,
                          color: theme.colorScheme.primary,
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppI18n.t(context, 'app.title'),
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              AppI18n.t(context, 'landing.subtitle'),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppI18n.t(context, 'landing.scan_mode'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SegmentedButton<SeedScanMode>(
                          segments: [
                            ButtonSegment<SeedScanMode>(
                              value: SeedScanMode.variety,
                              label: Text(AppI18n.t(context, 'mode.variety')),
                              icon: const Icon(Icons.category_outlined, size: 20),
                            ),
                            ButtonSegment<SeedScanMode>(
                              value: SeedScanMode.viability,
                              label: Text(AppI18n.t(context, 'mode.viability')),
                              icon: const Icon(Icons.favorite_outline, size: 20),
                            ),
                          ],
                          selected: {_mode},
                          onSelectionChanged: (s) {
                            setState(() => _mode = s.first);
                          },
                          showSelectedIcon: false,
                          emptySelectionAllowed: false,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          AppI18n.t(context, 'landing.language'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SegmentedButton<AppLanguage>(
                          segments: [
                            ButtonSegment<AppLanguage>(
                              value: AppLanguage.english,
                              label: Text(AppI18n.t(context, 'lang.english')),
                            ),
                            ButtonSegment<AppLanguage>(
                              value: AppLanguage.waray,
                              label: Text(AppI18n.t(context, 'lang.waray')),
                            ),
                            ButtonSegment<AppLanguage>(
                              value: AppLanguage.tagalog,
                              label: Text(AppI18n.t(context, 'lang.tagalog')),
                            ),
                          ],
                          selected: {language},
                          onSelectionChanged: (s) => languageController.value = s.first,
                          showSelectedIcon: false,
                          emptySelectionAllowed: false,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: widget.cameras.isEmpty
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ScanGuidelinesScreen(
                                cameras: widget.cameras,
                                scanMode: _mode,
                                isRealtime: true,
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.videocam_outlined),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(AppI18n.t(context, 'landing.realtime')),
                  ),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: widget.cameras.isEmpty
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ScanGuidelinesScreen(
                                cameras: widget.cameras,
                                scanMode: _mode,
                                isRealtime: false,
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(AppI18n.t(context, 'landing.capture')),
                  ),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (widget.cameras.isEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      AppI18n.t(context, 'landing.no_camera'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

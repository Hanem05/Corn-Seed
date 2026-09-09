import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../l10n/app_i18n.dart';
import '../models/seed_scan_mode.dart';
import '../theme/app_theme.dart';
import 'scan_guidelines_screen.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key, required this.cameras});
  final List<CameraDescription> cameras;
  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  SeedScanMode _mode = SeedScanMode.variety;
  void _start(bool live) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ScanGuidelinesScreen(
          cameras: widget.cameras, scanMode: _mode, isRealtime: live)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final language = AppLanguageScope.controllerOf(context);
    String t(String key) => AppI18n.t(context, key);
    return Scaffold(
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: ListView(padding: const EdgeInsets.all(24), children: [
        Row(children: [
          Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppTheme.forest,
                  borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.grass_rounded, color: AppTheme.gold)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(t('app.title'),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700))),
          PopupMenuButton<AppLanguage>(
              tooltip: t('landing.language'),
              icon: const Icon(Icons.translate_rounded),
              initialValue: language.value,
              onSelected: (value) => language.value = value,
              itemBuilder: (_) => AppLanguage.values
                  .map((value) => CheckedPopupMenuItem(
                      value: value,
                      checked: language.value == value,
                      child: Text(t('lang.${value.name}'))))
                  .toList()),
        ]),
        const SizedBox(height: 36),
        Text(t('design.headline'), style: theme.textTheme.headlineLarge),
        const SizedBox(height: 12),
        Text(t('design.intro'),
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 28),
        Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: AppTheme.forest,
                borderRadius: BorderRadius.circular(28)),
            child: Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Icon(Icons.center_focus_strong_rounded,
                        color: AppTheme.gold, size: 30),
                    const SizedBox(height: 20),
                    Text(t('design.hero'),
                        style: theme.textTheme.titleLarge
                            ?.copyWith(color: Colors.white)),
                    const SizedBox(height: 8),
                    Text(t('design.hero_body'),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: const Color(0xFFC7D8CB))),
                  ])),
              const SizedBox(width: 16),
              const Icon(Icons.grass_rounded, size: 72, color: AppTheme.gold),
            ])),
        const SizedBox(height: 32),
        Text('01  /  ${t('landing.scan_mode')}',
            style: theme.textTheme.labelLarge?.copyWith(
                letterSpacing: 1, color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 14),
        ...SeedScanMode.values.map((mode) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ModeCard(
                selected: _mode == mode,
                title: t('mode.${mode.name}'),
                description: t('design.${mode.name}_body'),
                icon: mode == SeedScanMode.variety
                    ? Icons.grain_rounded
                    : Icons.eco_outlined,
                onTap: () => setState(() => _mode = mode)))),
        const SizedBox(height: 22),
        Text('02  /  ${t('design.scan_method')}',
            style: theme.textTheme.labelLarge?.copyWith(
                letterSpacing: 1, color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 14),
        FilledButton.icon(
            onPressed: (widget.cameras.isEmpty && !kIsWeb) ? null : () => _start(false),
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text(t('landing.capture'))),
        const SizedBox(height: 10),
        OutlinedButton.icon(
            onPressed: (widget.cameras.isEmpty && !kIsWeb) ? null : () => _start(true),
            icon: const Icon(Icons.sensors_rounded),
            label: Text(t('landing.realtime'))),
        if ((widget.cameras.isEmpty && !kIsWeb))
          Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(t('landing.no_camera'),
                  style: TextStyle(color: theme.colorScheme.error))),
        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.light_mode_outlined, size: 16),
          const SizedBox(width: 8),
          Flexible(
              child: Text(t('design.footer'), style: theme.textTheme.bodySmall))
        ]),
      ]),
    ))));
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard(
      {required this.selected,
      required this.title,
      required this.description,
      required this.icon,
      required this.onTap});
  final bool selected;
  final String title, description;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
      selected: selected,
      child: Material(
        color: selected ? const Color(0xFFE7EDE3) : Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
                color: selected ? AppTheme.forest : const Color(0xFFDCE1D8),
                width: selected ? 1.5 : 1)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: onTap,
            child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(children: [
                  Icon(icon, size: 28, color: AppTheme.forest),
                  const SizedBox(width: 16),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(description,
                            style: Theme.of(context).textTheme.bodyMedium)
                      ])),
                  const SizedBox(width: 12),
                  Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color:
                          selected ? AppTheme.forest : const Color(0xFF9DA99E)),
                ]))),
      ));
}

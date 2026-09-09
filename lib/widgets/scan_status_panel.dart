import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A legible camera status surface independent of the preview's colors.
class ScanStatusPanel extends StatelessWidget {
  const ScanStatusPanel(
      {super.key,
      required this.title,
      required this.message,
      this.busy = false,
      this.count});
  final String title, message;
  final bool busy;
  final int? count;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: AppTheme.forest.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white24)),
        child: Row(children: [
          if (busy)
            const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: AppTheme.gold, strokeWidth: 2))
          else
            const Icon(Icons.center_focus_strong_rounded, color: AppTheme.gold),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
                const SizedBox(height: 4),
                Text(message,
                    style: const TextStyle(
                        color: Color(0xFFD3E0D7), fontSize: 13, height: 1.4))
              ])),
          if (count != null) ...[
            const SizedBox(width: 12),
            Text('$count',
                style: const TextStyle(
                    color: AppTheme.gold,
                    fontSize: 30,
                    fontWeight: FontWeight.w700))
          ],
        ]),
      );
}

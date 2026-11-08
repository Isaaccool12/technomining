import 'package:engineer/features/reports/application/report_print.dart';
import 'package:engineer/features/reports/domain/tolerance.dart';
import 'package:flutter/material.dart';

/// Background and foreground of a status in the current theme.
({Color background, Color foreground, IconData icon}) statusStyle(
  ToleranceStatus status,
  Brightness brightness,
) {
  final dark = brightness == Brightness.dark;
  return switch (status) {
    ToleranceStatus.within => (
      background: dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
      foreground: dark ? Colors.black : Colors.white,
      icon: Icons.check_circle,
    ),
    ToleranceStatus.nearLimit => (
      background: dark ? const Color(0xFFFFD54F) : const Color(0xFFF9A825),
      foreground: Colors.black,
      icon: Icons.error,
    ),
    ToleranceStatus.outside => (
      background: dark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828),
      foreground: dark ? Colors.black : Colors.white,
      icon: Icons.cancel,
    ),
    ToleranceStatus.noTolerance => (
      background: dark ? const Color(0xFF5F6368) : const Color(0xFFDADCE0),
      foreground: dark ? Colors.white : Colors.black,
      icon: Icons.help_outline,
    ),
  };
}

/// Status of a reading: colour, icon and text together, never colour alone.
class ToleranceBadge extends StatelessWidget {
  /// Creates the badge.
  const ToleranceBadge({required this.status, super.key});

  /// Status to show.
  final ToleranceStatus status;

  @override
  Widget build(BuildContext context) {
    final style = statusStyle(status, Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, color: style.foreground, size: 22),
          const SizedBox(width: 6),
          Text(
            statusLabel(status),
            style: TextStyle(
              color: style.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

export 'entitlements.dart';

/// Small "Premium" pill rendered next to gated controls so users see
/// what's locked. Visual only — does not gate input on its own.
class PremiumPill extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final double fontSize;
  final String label;

  const PremiumPill({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    this.fontSize = 10,
    this.label = 'Premium',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFEC4899)],
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.sparkles, size: fontSize + 2, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps a child and visually locks it (greyed + pill overlay) when
/// `locked` is true. Tapping a locked control shows a snackbar.
class PremiumLock extends StatelessWidget {
  final bool locked;
  final Widget child;
  final String featureName;

  const PremiumLock({
    super.key,
    required this.locked,
    required this.child,
    required this.featureName,
  });

  @override
  Widget build(BuildContext context) {
    if (!locked) return child;
    return Stack(
      children: [
        Opacity(opacity: 0.45, child: IgnorePointer(child: child)),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$featureName is a Premium feature.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const PremiumPill(),
          ),
        ),
      ],
    );
  }
}

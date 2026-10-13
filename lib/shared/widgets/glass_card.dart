import 'dart:ui';
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/glass_tokens.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? borderRadius;
  final Color? backgroundColor;
  final Color? borderColor;
  final double? blur;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius,
    this.backgroundColor,
    this.borderColor,
    this.blur,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = backgroundColor ??
        (isDark ? AppColors.glassDark : AppColors.glassLight);
    final border = borderColor ??
        (isDark ? AppColors.glassBorderDark : AppColors.glassBorderLight);
    final radius = borderRadius ?? GlassTokens.radiusLg;

    Widget card = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: blur ?? GlassTokens.blurMd,
          sigmaY: blur ?? GlassTokens.blurMd,
        ),
        child: Container(
          padding: padding ?? const EdgeInsets.all(GlassTokens.spacingLg),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: border, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                blurRadius: GlassTokens.shadowMd,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );

    if (margin != null) {
      card = Padding(padding: margin!, child: card);
    }

    if (onTap != null || onLongPress != null) {
      return GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: card,
      );
    }

    return card;
  }
}

import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/glass_tokens.dart';

class GradientBackground extends StatelessWidget {
  final Widget child;

  const GradientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [AppColors.gradientDarkStart, AppColors.gradientDarkEnd]
              : [AppColors.gradientLightStart, AppColors.gradientLightEnd],
        ),
      ),
      child: child,
    );
  }
}

class SoftButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool isSmall;

  const SoftButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isPrimary = false,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isPrimary) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        icon: icon != null ? Icon(icon, size: isSmall ? 16 : 20) : const SizedBox.shrink(),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.symmetric(
            horizontal: isSmall ? 16 : 24,
            vertical: isSmall ? 8 : 14,
          ),
          textStyle: TextStyle(fontSize: isSmall ? 13 : 15, fontWeight: FontWeight.w600),
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: icon != null ? Icon(icon, size: isSmall ? 16 : 20) : const SizedBox.shrink(),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
        side: BorderSide(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: isSmall ? 16 : 24,
          vertical: isSmall ? 8 : 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
        ),
        textStyle: TextStyle(fontSize: isSmall ? 13 : 15, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark
        ? Color.lerp(color, Colors.white, 0.62)!
        : Color.lerp(color, Colors.black, 0.2)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(GlassTokens.radiusFull),
        border: Border.all(color: foreground.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';

/// Round profile picture: photo, then initials, then a person glyph for
/// anonymous users.
class ProfileAvatar extends StatelessWidget {
  final User? user;
  final double size;

  const ProfileAvatar({super.key, required this.user, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final signedIn = user != null && !user!.isAnonymous;
    final photo = signedIn ? user!.photoURL : null;
    final initials = signedIn ? _initials(user!) : null;

    Widget child;
    if (photo != null && photo.isNotEmpty) {
      child = CachedNetworkImage(
        imageUrl: photo,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => _fallback(initials, isDark),
      );
    } else {
      child = _fallback(initials, isDark);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: signedIn
              ? context.accentText
              : (isDark ? AppColors.borderDark : AppColors.borderLight),
          width: 1.5,
        ),
      ),
      child: ClipOval(child: child),
    );
  }

  Widget _fallback(String? initials, bool isDark) {
    return Container(
      color: initials != null
          ? AppColors.primary
          : (isDark ? AppColors.cardDark : AppColors.cardLight),
      alignment: Alignment.center,
      child: initials != null
          ? Text(
              initials,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.38,
                fontWeight: FontWeight.w700,
              ),
            )
          : Icon(
              CupertinoIcons.person_fill,
              size: size * 0.55,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
    );
  }

  static String? _initials(User user) {
    final source = (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim()
        : (user.email ?? '').split('@').first;
    final parts = source
        .split(RegExp(r'[\s._-]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;
    final letters = parts.length == 1
        ? parts.first.substring(0, 1)
        : '${parts.first[0]}${parts.last[0]}';
    return letters.toUpperCase();
  }
}

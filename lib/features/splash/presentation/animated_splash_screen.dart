import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/providers/onboarding_prefs.dart';

class AnimatedSplashScreen extends ConsumerStatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  ConsumerState<AnimatedSplashScreen> createState() =>
      _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends ConsumerState<AnimatedSplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2200), _navigate);
  }

  Future<void> _navigate() async {
    if (!mounted) return;
    // Wait for prefs to load (max ~600ms)
    for (var i = 0; i < 12; i++) {
      if (ref.read(onboardingPrefsProvider).ready) break;
      await Future.delayed(const Duration(milliseconds: 50));
    }
    if (!mounted) return;
    final prefs = ref.read(onboardingPrefsProvider);
    if (!prefs.wizardCompleted) {
      context.go('/onboarding');
    } else {
      context.go('/sessions');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated sparkle icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/icon/app_icon.png',
                  fit: BoxFit.cover,
                ),
              ),
            )
                .animate()
                .scale(
                  begin: const Offset(0.3, 0.3),
                  end: const Offset(1, 1),
                  duration: 600.ms,
                  curve: Curves.elasticOut,
                )
                .fadeIn(duration: 300.ms),
            const SizedBox(height: 24),
            // App name
            Text(
              'A1111 Mini',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppColors.textPrimaryDark,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
            )
                .animate(delay: 400.ms)
                .fadeIn(duration: 500.ms)
                .slideY(begin: 0.3, end: 0, duration: 500.ms, curve: Curves.easeOut),
            const SizedBox(height: 8),
            Text(
              'Stable Diffusion Suite',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondaryDark,
                    letterSpacing: 1.0,
                  ),
            )
                .animate(delay: 700.ms)
                .fadeIn(duration: 500.ms),
          ],
        ),
      ),
    );
  }
}

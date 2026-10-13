import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/glass_tokens.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/security/app_lock.dart';
import '../../../core/utils/image_storage.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/platform_icon.dart';
import 'providers_section.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeMode = ref.watch(themeModeProvider);
    final genDefaults = ref.watch(generationDefaultsProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.gradientDarkStart : AppColors.gradientLightStart,
        appBar: AppBar(
          systemOverlayStyle:
              isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            'Settings',
            style: TextStyle(
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
              fontWeight: FontWeight.w600,
            ),
          ),
          leading: IconButton(
            icon: PlatformIcon(
              material: Icons.arrow_back,
              cupertino: CupertinoIcons.back,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            ),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go('/sessions');
              }
            },
          ),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [AppColors.gradientDarkStart, AppColors.gradientDarkEnd]
                  : [AppColors.gradientLightStart, AppColors.gradientLightEnd],
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              GlassTokens.spacingLg,
              GlassTokens.spacingMd,
              GlassTokens.spacingLg,
              GlassTokens.spacingXxl,
            ),
            children: [
            const SizedBox(height: GlassTokens.spacingSm),

            const ProvidersSection(),
            const SizedBox(height: GlassTokens.spacingXl),

            // Appearance
            Text('Appearance', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: GlassTokens.spacingSm),
            GlassCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _ThemeTile(
                    title: 'Light',
                    icon: Icons.light_mode,
                    selected: themeMode == 'light',
                    onTap: () => ref.read(themeModeProvider.notifier).state = 'light',
                  ),
                  const Divider(height: 0.5, indent: 56),
                  _ThemeTile(
                    title: 'Dark',
                    icon: Icons.dark_mode,
                    selected: themeMode == 'dark',
                    onTap: () => ref.read(themeModeProvider.notifier).state = 'dark',
                  ),
                  const Divider(height: 0.5, indent: 56),
                  _ThemeTile(
                    title: 'System',
                    icon: Icons.settings_brightness,
                    selected: themeMode == 'system',
                    onTap: () => ref.read(themeModeProvider.notifier).state = 'system',
                  ),
                ],
              ),
            ),
            const SizedBox(height: GlassTokens.spacingXl),

            // Generation Defaults
            Text('Generation', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: GlassTokens.spacingSm),
            GlassCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const PlatformIcon(
                      material: Icons.tune,
                      cupertino: CupertinoIcons.slider_horizontal_3,
                    ),
                    title: const Text('Generation Defaults'),
                    subtitle: Text(
                      '${genDefaults.samplerName} • ${genDefaults.steps} steps • CFG ${genDefaults.cfgScale.toStringAsFixed(1)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const PlatformIcon(
                      material: Icons.chevron_right,
                      cupertino: CupertinoIcons.chevron_right,
                    ),
                    onTap: () => context.push('/generation-defaults'),
                  ),
                  const Divider(height: 0.5, indent: 56),
                  const _GenerationTimeoutTile(),
                ],
              ),
            ),
            const SizedBox(height: GlassTokens.spacingXl),

            // Display
            Text('Display', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: GlassTokens.spacingSm),
            GlassCard(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                secondary: const Icon(Icons.analytics_outlined),
                title: const Text('Nerd Stats'),
                subtitle: const Text('Show detailed generation info with images'),
                value: genDefaults.showNerdStats,
                onChanged: (v) => ref
                    .read(generationDefaultsProvider.notifier)
                    .update(genDefaults.copyWith(showNerdStats: v)),
              ),
            ),
            const SizedBox(height: GlassTokens.spacingXl),

            // Security
            Text('Security', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: GlassTokens.spacingSm),
            GlassCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  Builder(builder: (context) {
                    final lock = ref.watch(appLockProvider);
                    return ListTile(
                      leading: const Icon(Icons.fingerprint),
                      title: const Text('App Lock'),
                      subtitle: const Text('PIN or biometric authentication'),
                      trailing: Switch(
                        value: lock.enabled,
                        onChanged: lock.ready
                            ? (v) async {
                                final res = await ref
                                    .read(appLockProvider.notifier)
                                    .setEnabledDetailed(v);
                                if (!context.mounted) return;
                                switch (res) {
                                  case AppLockAuthResult.success:
                                    break;
                                  case AppLockAuthResult.cancelled:
                                    // User cancelled — silent.
                                    break;
                                  case AppLockAuthResult.notAvailable:
                                    await showDialog<void>(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: const Text(
                                            'Authentication Unavailable'),
                                        content: const Text(
                                          'Set up Face ID, Touch ID, or a device '
                                          'passcode in your iOS Settings to use '
                                          'App Lock.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('OK'),
                                          ),
                                        ],
                                      ),
                                    );
                                    break;
                                  case AppLockAuthResult.failed:
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Authentication failed. Please try again.'),
                                      ),
                                    );
                                    break;
                                }
                              }
                            : null,
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: GlassTokens.spacingXl),

            // Storage
            Text('Storage', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: GlassTokens.spacingSm),
            GlassCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  FutureBuilder<int>(
                    future: ImageStorage.getTotalStorageBytes(),
                    builder: (context, snapshot) {
                      final bytes = snapshot.data ?? 0;
                      final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
                      return ListTile(
                        leading: const Icon(Icons.storage),
                        title: const Text('Image Storage'),
                        subtitle: Text('$mb MB used'),
                      );
                    },
                  ),
                  const Divider(height: 0.5, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.delete_sweep),
                    title: const Text('Clear Cache'),
                    onTap: () => _confirmClearCache(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: GlassTokens.spacingXl),

            // About
            Text('About', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: GlassTokens.spacingSm),
            GlassCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snap) {
                      final v = snap.data;
                      final subtitle = v == null
                          ? 'Loading…'
                          : 'Version ${v.version} (${v.buildNumber})';
                      return ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: const Text('A1111 Mini'),
                        subtitle: Text(subtitle),
                      );
                    },
                  ),
                  const Divider(height: 0.5, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.book_outlined),
                    title: const Text('A1111 Documentation'),
                    trailing: const Icon(Icons.open_in_new, size: 16),
                    onTap: () {
                      // Open docs URL
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: GlassTokens.spacingXxl),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmClearCache(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text(
          'Deletes temporary files (such as photos picked for img2img) and '
          'clears the in-memory image cache. Your generated images, gallery '
          'and sessions are not affected.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final messenger = ScaffoldMessenger.of(context);
              final failed = await _clearCache();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    failed == 0
                        ? 'Cache cleared'
                        : 'Cache cleared ($failed files in use were kept)',
                  ),
                ),
              );
            },
            child: Text('Clear', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

/// Empties the app's temp dir and Flutter's decoded image cache. Gallery
/// images live in the documents dir and are never touched. Returns how many
/// entries could not be deleted.
Future<int> _clearCache() async {
  var failed = 0;
  try {
    final tmp = await getTemporaryDirectory();
    if (await tmp.exists()) {
      await for (final entity in tmp.list(followLinks: false)) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {
          failed++;
        }
      }
    }
  } catch (_) {
    failed++;
  }
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
  return failed;
}

class _ThemeTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeTile({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: PlatformIcon(
        material: icon,
        cupertino: icon == Icons.light_mode
            ? CupertinoIcons.sun_max
            : icon == Icons.dark_mode
                ? CupertinoIcons.moon
                : CupertinoIcons.settings,
        color: selected ? context.accentText : null,
      ),
      title: Text(title),
      trailing: selected
          ? const PlatformIcon(
              material: Icons.check_circle,
              cupertino: CupertinoIcons.checkmark_circle_fill,
              color: AppColors.primary,
              size: 20,
            )
          : null,
      onTap: onTap,
    );
  }
}

const _timeoutPresets = <int>[
  1,
  5,
  10,
  15,
  30,
  60,
  120,
  240,
  720,
  1440,
];

class _GenerationTimeoutTile extends ConsumerWidget {
  const _GenerationTimeoutTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minutes = ref.watch(generationTimeoutMinutesProvider);
    return ListTile(
      leading: const PlatformIcon(
        material: Icons.timer_outlined,
        cupertino: CupertinoIcons.timer,
      ),
      title: const Text('Generation Timeout'),
      subtitle: Text(
        'Wait up to ${formatGenerationTimeout(minutes)} for slower servers',
      ),
      trailing: const PlatformIcon(
        material: Icons.chevron_right,
        cupertino: CupertinoIcons.chevron_right,
      ),
      onTap: () => _showTimeoutSheet(context, ref),
    );
  }

  void _showTimeoutSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _GenerationTimeoutSheet(),
    );
  }
}

class _GenerationTimeoutSheet extends ConsumerWidget {
  const _GenerationTimeoutSheet();

  static double _sliderFromMinutes(int minutes) {
    final clamped = minutes.clamp(
      kGenerationTimeoutMinMinutes,
      kGenerationTimeoutMaxMinutes,
    );
    return math.log(clamped) / math.log(kGenerationTimeoutMaxMinutes);
  }

  static int _minutesFromSlider(double value) {
    final minutes = math
        .pow(kGenerationTimeoutMaxMinutes, value)
        .round()
        .clamp(kGenerationTimeoutMinMinutes, kGenerationTimeoutMaxMinutes);
    return minutes;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minutes = ref.watch(generationTimeoutMinutesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        24 + MediaQuery.of(context).viewPadding.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Generation Timeout',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'How long to wait for an image before giving up. Use a longer value for Colab or slow GPUs.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
          ),
          const SizedBox(height: 20),
          Text(
            formatGenerationTimeout(minutes),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
          ),
          Slider(
            value: _sliderFromMinutes(minutes),
            min: 0,
            max: 1,
            onChanged: (v) => ref
                .read(generationTimeoutMinutesProvider.notifier)
                .setMinutes(_minutesFromSlider(v)),
          ),
          Row(
            children: [
              Text('1 min', style: Theme.of(context).textTheme.labelSmall),
              const Spacer(),
              Text('1 day', style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _timeoutPresets.map((preset) {
              final selected = minutes == preset;
              return ChoiceChip(
                label: Text(formatGenerationTimeout(preset)),
                selected: selected,
                onSelected: (_) => ref
                    .read(generationTimeoutMinutesProvider.notifier)
                    .setMinutes(preset),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

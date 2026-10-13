import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/glass_tokens.dart';
import '../../../core/premium/entitlements.dart';
import '../../../core/providers/core_providers.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/platform_icon.dart';

class GenerationDefaultsScreen extends ConsumerWidget {
  const GenerationDefaultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final genDefaults = ref.watch(generationDefaultsProvider);
    final maxBatch = ref.watch(hasFeatureProvider(PremiumFeature.largeBatch))
        ? kPremiumMaxBatch
        : kFreeMaxBatch;
    final samplers = ref.watch(serverSamplersProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.gradientDarkStart : AppColors.gradientLightStart,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            'Generation Defaults',
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
                context.go('/settings');
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
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    samplers.when(
                      data: (list) => DropdownButtonFormField<String>(
                        value: list.any((s) => s.name == genDefaults.samplerName)
                            ? genDefaults.samplerName
                            : (list.isNotEmpty ? list.first.name : null),
                        decoration: const InputDecoration(labelText: 'Default Sampler'),
                        items: list
                            .map((s) => DropdownMenuItem(
                                  value: s.name,
                                  child: Text(s.name, overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            ref
                                .read(generationDefaultsProvider.notifier)
                                .update(genDefaults.copyWith(samplerName: v));
                          }
                        },
                      ),
                      loading: () => const InputDecorator(
                        decoration: InputDecoration(labelText: 'Default Sampler'),
                        child: Text('Connect to server...'),
                      ),
                      error: (_, __) => const InputDecorator(
                        decoration: InputDecoration(labelText: 'Default Sampler'),
                        child: Text('Connect to server...'),
                      ),
                    ),
                    const SizedBox(height: GlassTokens.spacingMd),
                    Row(
                      children: [
                        const SizedBox(width: 50, child: Text('Steps')),
                        Expanded(
                          child: Slider(
                            value: genDefaults.steps.toDouble(),
                            min: 1,
                            max: 150,
                            divisions: 149,
                            label: '${genDefaults.steps}',
                            onChanged: (v) => ref
                                .read(generationDefaultsProvider.notifier)
                                .update(genDefaults.copyWith(steps: v.round())),
                          ),
                        ),
                        SizedBox(
                          width: 36,
                          child: Text('${genDefaults.steps}', textAlign: TextAlign.center),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const SizedBox(width: 50, child: Text('CFG')),
                        Expanded(
                          child: Slider(
                            value: genDefaults.cfgScale,
                            min: 1,
                            max: 30,
                            divisions: 58,
                            label: genDefaults.cfgScale.toStringAsFixed(1),
                            onChanged: (v) => ref
                                .read(generationDefaultsProvider.notifier)
                                .update(genDefaults.copyWith(cfgScale: v)),
                          ),
                        ),
                        SizedBox(
                          width: 36,
                          child: Text(genDefaults.cfgScale.toStringAsFixed(1), textAlign: TextAlign.center),
                        ),
                      ],
                    ),
                    Text('Default Size', style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _sizeChip('512×512', 512, 512, genDefaults, ref),
                        _sizeChip('512×768', 512, 768, genDefaults, ref),
                        _sizeChip('768×512', 768, 512, genDefaults, ref),
                        _sizeChip('768×768', 768, 768, genDefaults, ref),
                        _sizeChip('1024×1024', 1024, 1024, genDefaults, ref),
                      ],
                    ),
                    const SizedBox(height: GlassTokens.spacingMd),
                    Row(
                      children: [
                        const SizedBox(width: 80, child: Text('Batch Size')),
                        Expanded(
                          child: Slider(
                            value: genDefaults.batchSize
                                .clamp(1, maxBatch)
                                .toDouble(),
                            min: 1,
                            max: maxBatch.toDouble(),
                            divisions: maxBatch - 1,
                            label: '${genDefaults.batchSize}',
                            onChanged: (v) => ref
                                .read(generationDefaultsProvider.notifier)
                                .update(genDefaults.copyWith(batchSize: v.round())),
                          ),
                        ),
                        SizedBox(
                          width: 36,
                          child: Text('${genDefaults.batchSize.clamp(1, maxBatch)}', textAlign: TextAlign.center),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Restore Faces'),
                      value: genDefaults.restoreFaces,
                      onChanged: (v) => ref
                          .read(generationDefaultsProvider.notifier)
                          .update(genDefaults.copyWith(restoreFaces: v)),
                    ),
                    const Divider(),
                    // Scheduler
                    Builder(builder: (_) {
                      final schedulers = ref.watch(serverSchedulersProvider);
                      return schedulers.when(
                        data: (list) {
                          final names = ['Automatic', ...list.map((s) => s.name)];
                          final value = (genDefaults.scheduler == null ||
                                  !names.contains(genDefaults.scheduler))
                              ? 'Automatic'
                              : genDefaults.scheduler!;
                          return DropdownButtonFormField<String>(
                            value: value,
                            decoration:
                                const InputDecoration(labelText: 'Scheduler'),
                            items: names
                                .map((n) => DropdownMenuItem(
                                    value: n,
                                    child: Text(n,
                                        overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: (v) => ref
                                .read(generationDefaultsProvider.notifier)
                                .update(genDefaults.copyWith(
                                  scheduler: v == 'Automatic' ? null : v,
                                )),
                          );
                        },
                        loading: () => const InputDecorator(
                          decoration: InputDecoration(labelText: 'Scheduler'),
                          child: Text('Connect to server\u2026'),
                        ),
                        error: (_, __) => const SizedBox.shrink(),
                      );
                    }),
                    const SizedBox(height: GlassTokens.spacingMd),
                    // VAE
                    Builder(builder: (_) {
                      final vaes = ref.watch(serverVaesProvider);
                      return vaes.when(
                        data: (list) {
                          final entries = ['Automatic', 'None', ...list.map((v) => v.modelName)];
                          final value = entries.contains(genDefaults.vae)
                              ? genDefaults.vae
                              : 'Automatic';
                          return DropdownButtonFormField<String>(
                            value: value,
                            decoration:
                                const InputDecoration(labelText: 'VAE'),
                            items: entries
                                .map((n) => DropdownMenuItem(
                                    value: n,
                                    child: Text(n,
                                        overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: (v) => ref
                                .read(generationDefaultsProvider.notifier)
                                .update(genDefaults.copyWith(
                                    vae: v ?? 'Automatic')),
                          );
                        },
                        loading: () => const InputDecorator(
                          decoration: InputDecoration(labelText: 'VAE'),
                          child: Text('Connect to server\u2026'),
                        ),
                        error: (_, __) => const SizedBox.shrink(),
                      );
                    }),
                    const SizedBox(height: GlassTokens.spacingMd),
                    Row(
                      children: [
                        const SizedBox(width: 100, child: Text('Distilled CFG')),
                        Expanded(
                          child: Slider(
                            value: genDefaults.distilledCfgScale.clamp(0, 30),
                            min: 0,
                            max: 30,
                            divisions: 60,
                            label: genDefaults.distilledCfgScale.toStringAsFixed(1),
                            onChanged: (v) => ref
                                .read(generationDefaultsProvider.notifier)
                                .update(genDefaults.copyWith(distilledCfgScale: v)),
                          ),
                        ),
                        SizedBox(
                          width: 36,
                          child: Text(
                              genDefaults.distilledCfgScale.toStringAsFixed(1),
                              textAlign: TextAlign.center),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: GlassTokens.spacingLg),
              // ── Hires Fix ─────────────────────────────────────
              Text('Hires Fix', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: GlassTokens.spacingSm),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable Hires Fix by default'),
                      value: genDefaults.hiresEnabled,
                      onChanged: (v) => ref
                          .read(generationDefaultsProvider.notifier)
                          .update(genDefaults.copyWith(hiresEnabled: v)),
                    ),
                    Builder(builder: (_) {
                      final upscalers = ref.watch(serverUpscalersProvider);
                      return upscalers.when(
                        data: (list) {
                          final names = list.map((u) => u.name).toList();
                          if (names.isEmpty) names.add('Latent');
                          final value = names.contains(genDefaults.hiresUpscaler)
                              ? genDefaults.hiresUpscaler
                              : names.first;
                          return DropdownButtonFormField<String>(
                            value: value,
                            decoration:
                                const InputDecoration(labelText: 'Upscaler'),
                            items: names
                                .map((n) => DropdownMenuItem(
                                    value: n,
                                    child: Text(n,
                                        overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: (v) => ref
                                .read(generationDefaultsProvider.notifier)
                                .update(genDefaults.copyWith(
                                    hiresUpscaler: v ?? 'Latent')),
                          );
                        },
                        loading: () => const InputDecorator(
                          decoration: InputDecoration(labelText: 'Upscaler'),
                          child: Text('Connect to server\u2026'),
                        ),
                        error: (_, __) => const SizedBox.shrink(),
                      );
                    }),
                    Row(
                      children: [
                        const SizedBox(width: 60, child: Text('Scale')),
                        Expanded(
                          child: Slider(
                            value: genDefaults.hiresScale.clamp(1, 4),
                            min: 1,
                            max: 4,
                            divisions: 30,
                            label: '${genDefaults.hiresScale.toStringAsFixed(2)}\u00d7',
                            onChanged: (v) => ref
                                .read(generationDefaultsProvider.notifier)
                                .update(genDefaults.copyWith(hiresScale: v)),
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          child: Text(
                              '${genDefaults.hiresScale.toStringAsFixed(2)}\u00d7',
                              textAlign: TextAlign.center),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const SizedBox(width: 60, child: Text('Steps')),
                        Expanded(
                          child: Slider(
                            value: genDefaults.hiresSteps.toDouble().clamp(0, 80),
                            min: 0,
                            max: 80,
                            divisions: 80,
                            label: '${genDefaults.hiresSteps}',
                            onChanged: (v) => ref
                                .read(generationDefaultsProvider.notifier)
                                .update(genDefaults.copyWith(hiresSteps: v.round())),
                          ),
                        ),
                        SizedBox(
                          width: 36,
                          child: Text('${genDefaults.hiresSteps}',
                              textAlign: TextAlign.center),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const SizedBox(width: 80, child: Text('Denoising')),
                        Expanded(
                          child: Slider(
                            value: genDefaults.hiresDenoising.clamp(0, 1),
                            min: 0,
                            max: 1,
                            divisions: 20,
                            label:
                                genDefaults.hiresDenoising.toStringAsFixed(2),
                            onChanged: (v) => ref
                                .read(generationDefaultsProvider.notifier)
                                .update(genDefaults.copyWith(hiresDenoising: v)),
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: Text(
                              genDefaults.hiresDenoising.toStringAsFixed(2),
                              textAlign: TextAlign.center),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: GlassTokens.spacingLg),
              // ── Refiner ────────────────────────────────────────
              Text('Refiner', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: GlassTokens.spacingSm),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Builder(builder: (_) {
                      final models = ref.watch(serverModelsProvider);
                      return models.when(
                        data: (list) {
                          final names = ['None', ...list.map((m) => m.title)];
                          final value =
                              (genDefaults.refinerCheckpoint == null ||
                                      !names.contains(genDefaults.refinerCheckpoint))
                                  ? 'None'
                                  : genDefaults.refinerCheckpoint!;
                          return DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: value,
                            decoration: const InputDecoration(
                                labelText: 'Refiner Checkpoint'),
                            items: names
                                .map((n) => DropdownMenuItem(
                                    value: n,
                                    child: Text(n,
                                        overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: (v) => ref
                                .read(generationDefaultsProvider.notifier)
                                .update(genDefaults.copyWith(
                                  refinerCheckpoint: v == 'None' ? null : v,
                                )),
                          );
                        },
                        loading: () => const InputDecorator(
                          decoration:
                              InputDecoration(labelText: 'Refiner Checkpoint'),
                          child: Text('Connect to server\u2026'),
                        ),
                        error: (_, __) => const SizedBox.shrink(),
                      );
                    }),
                    Row(
                      children: [
                        const SizedBox(width: 80, child: Text('Switch at')),
                        Expanded(
                          child: Slider(
                            value: genDefaults.refinerSwitchAt.clamp(0, 1),
                            min: 0,
                            max: 1,
                            divisions: 20,
                            label:
                                genDefaults.refinerSwitchAt.toStringAsFixed(2),
                            onChanged: (v) => ref
                                .read(generationDefaultsProvider.notifier)
                                .update(genDefaults.copyWith(refinerSwitchAt: v)),
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: Text(
                              genDefaults.refinerSwitchAt.toStringAsFixed(2),
                              textAlign: TextAlign.center),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: GlassTokens.spacingLg),
              // ── Prompt Styles ──────────────────────────────────
              Text('Prompt Styles',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: GlassTokens.spacingSm),
              GlassCard(
                child: Builder(builder: (_) {
                  final styles = ref.watch(serverPromptStylesProvider);
                  return styles.when(
                    data: (list) {
                      if (list.isEmpty) {
                        return const Text('No prompt styles defined on server.');
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Applied to every generation by default.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: list.map((s) {
                              final selected =
                                  genDefaults.promptStyles.contains(s.name);
                              return FilterChip(
                                label: Text(s.name,
                                    style: const TextStyle(fontSize: 12)),
                                selected: selected,
                                onSelected: (v) {
                                  final next =
                                      List<String>.of(genDefaults.promptStyles);
                                  if (v) {
                                    if (!next.contains(s.name)) next.add(s.name);
                                  } else {
                                    next.remove(s.name);
                                  }
                                  ref
                                      .read(generationDefaultsProvider.notifier)
                                      .update(genDefaults.copyWith(
                                          promptStyles: next));
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      );
                    },
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) =>
                        const Text('Connect to server to manage styles.'),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sizeChip(
    String label,
    int w,
    int h,
    GenerationDefaults defaults,
    WidgetRef ref,
  ) {
    final selected = defaults.width == w && defaults.height == h;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => ref
          .read(generationDefaultsProvider.notifier)
          .update(defaults.copyWith(width: w, height: h)),
      visualDensity: VisualDensity.compact,
    );
  }
}

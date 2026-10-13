import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/glass_tokens.dart';
import '../../../core/models/generation_backend.dart';
import '../../../core/on_device/apple_ml_models.dart';
import '../../../core/on_device/apple_ml_providers.dart';
import '../../../core/providers/core_providers.dart';
import '../../generation/presentation/comfy_workflow_dropdown.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/platform_icon.dart';

class ProvidersSection extends ConsumerWidget {
  const ProvidersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(activeProviderProvider);
    final server = ref.watch(activeServerProvider);
    final appleModel = AppleMlCatalog.byId(ref.watch(selectedAppleMlModelIdProvider));
    final installed = ref.watch(appleMlInstalledIdsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Providers', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: GlassTokens.spacingSm),
        Row(
          children: [
            Expanded(
              child: _ProviderCard(
                backend: GenerationBackend.a1111,
                selected: backend == GenerationBackend.a1111,
                onTap: () => ref
                    .read(activeProviderProvider.notifier)
                    .set(GenerationBackend.a1111),
              ),
            ),
            const SizedBox(width: GlassTokens.spacingMd),
            Expanded(
              child: _ProviderCard(
                backend: GenerationBackend.comfyui,
                selected: backend == GenerationBackend.comfyui,
                onTap: () => ref
                    .read(activeProviderProvider.notifier)
                    .set(GenerationBackend.comfyui),
              ),
            ),
          ],
        ),
        const SizedBox(height: GlassTokens.spacingMd),
        _ProviderCard(
          backend: GenerationBackend.appleMl,
          selected: backend == GenerationBackend.appleMl,
          onTap: () => ref
              .read(activeProviderProvider.notifier)
              .set(GenerationBackend.appleMl),
        ),
        const SizedBox(height: GlassTokens.spacingMd),
        GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              if (backend == GenerationBackend.appleMl)
                ListTile(
                  leading: const PlatformIcon(
                    material: Icons.phone_iphone,
                    cupertino: CupertinoIcons.device_phone_portrait,
                  ),
                  title: const Text('On-device model'),
                  subtitle: Text(
                    appleModel != null
                        ? '${appleModel.name} · ${appleModel.sizeHint}'
                        : installed.maybeWhen(
                            data: (ids) => ids.isEmpty
                                ? 'None downloaded — tap to manage'
                                : 'Select a downloaded model',
                            orElse: () => 'Download a Core ML package',
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const PlatformIcon(
                    material: Icons.chevron_right,
                    cupertino: CupertinoIcons.chevron_right,
                  ),
                  onTap: () => context.push('/apple-ml-models'),
                )
              else
                ListTile(
                  leading: PlatformIcon(
                    material: backend == GenerationBackend.comfyui
                        ? Icons.account_tree_outlined
                        : Icons.dns_outlined,
                    cupertino: CupertinoIcons.desktopcomputer,
                  ),
                  title: const Text('Active Server'),
                  subtitle: Text(
                    server != null
                        ? '${server.name} · ${server.displayAddress}'
                        : 'None — add a ${backend.label} server',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (server != null) const _ActiveServerStatusDot(),
                      const SizedBox(width: 8),
                      const PlatformIcon(
                        material: Icons.chevron_right,
                        cupertino: CupertinoIcons.chevron_right,
                      ),
                    ],
                  ),
                  onTap: () => context.go('/servers'),
                ),
              if (backend == GenerationBackend.comfyui) ...[
                const Divider(height: 0.5, indent: 56),
                ListTile(
                  leading: const Icon(Icons.schema_outlined),
                  title: const Text('Workflow'),
                  subtitle: const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: ComfyWorkflowDropdown(
                      includeRefresh: false,
                      showLabel: false,
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Refresh workflows',
                    icon: const Icon(Icons.refresh),
                    onPressed: () {
                      ref.invalidate(comfyWorkflowsProvider);
                      ref.invalidate(comfyWorkflowDefaultsProvider);
                      ref.invalidate(serverModelsProvider);
                      ref.invalidate(serverVaesProvider);
                      ref.invalidate(serverLorasProvider);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Live reachability of the active server, from connectionStatusProvider.
class _ActiveServerStatusDot extends ConsumerWidget {
  const _ActiveServerStatusDot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionStatusProvider);
    final (color, label) = status.when(
      data: (s) => !s.connected
          ? (AppColors.error, s.error ?? 'Not connected')
          : s.warning != null
              ? (AppColors.warning, s.warning!)
              : (AppColors.success, 'Connected'),
      loading: () => (AppColors.warning, 'Checking…'),
      error: (e, _) => (AppColors.error, '$e'),
    );
    return Tooltip(
      message: label,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final GenerationBackend backend;
  final bool selected;
  final VoidCallback onTap;

  const _ProviderCard({
    required this.backend,
    required this.selected,
    required this.onTap,
  });

  IconData get _icon {
    switch (backend) {
      case GenerationBackend.comfyui:
        return Icons.account_tree_outlined;
      case GenerationBackend.appleMl:
        return Icons.phone_iphone;
      case GenerationBackend.a1111:
        return Icons.auto_awesome;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      padding: const EdgeInsets.all(GlassTokens.spacingMd),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _icon,
                color: selected ? context.accentText : null,
              ),
              const Spacer(),
              if (selected)
                PlatformIcon(
                  material: Icons.check_circle,
                  cupertino: CupertinoIcons.checkmark_circle_fill,
                  color: context.accentText,
                  size: 20,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            backend.label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected ? context.accentText : null,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            backend.subtitle,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
          ),
        ],
      ),
    );
  }
}

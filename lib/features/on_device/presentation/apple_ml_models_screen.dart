import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/glass_tokens.dart';
import '../../../core/api/apple_ml_sd_plugin.dart';
import '../../../core/on_device/apple_ml_downloader.dart';
import '../../../core/on_device/apple_ml_models.dart';
import '../../../core/on_device/apple_ml_providers.dart';
import '../../../core/providers/core_providers.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/platform_icon.dart';

class AppleMlModelsScreen extends ConsumerWidget {
  const AppleMlModelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final installed = ref.watch(appleMlInstalledIdsProvider);
    final downloads = ref.watch(appleMlDownloadControllerProvider);
    final selectedId = ref.watch(selectedAppleMlModelIdProvider);

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        leading: IconButton(
          icon: PlatformIcon(
            material: Icons.arrow_back,
            cupertino: CupertinoIcons.back,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/settings');
            }
          },
        ),
        title: Text(
          'On-device models',
          style: TextStyle(
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          GlassTokens.spacingLg,
          GlassTokens.spacingMd,
          GlassTokens.spacingLg,
          GlassTokens.spacingXxl,
        ),
        children: [
          Text(
            'Download Apple Core ML Stable Diffusion packages from Hugging Face and generate on this iPhone or iPad. You can leave the app — iOS keeps the download going, with progress on the Lock Screen and Dynamic Island.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
          ),
          const SizedBox(height: GlassTokens.spacingMd),
          FutureBuilder<String>(
            future: AppleMlSdPlugin.osVersion(),
            builder: (context, snapshot) {
              final version = snapshot.data;
              return Text(
                Platform.isIOS
                    ? 'This device is running iOS ${version ?? '…'}. SD 1.5 needs 16.2+; SDXL needs 17+.'
                    : 'On-device Apple ML is iOS-only.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
              );
            },
          ),
          const SizedBox(height: GlassTokens.spacingXl),
          ...AppleMlCatalog.models.map((model) {
            final isInstalled =
                installed.maybeWhen(data: (ids) => ids.contains(model.id), orElse: () => false);
            final progress = downloads[model.id];
            final selected = selectedId == model.id;
            return Padding(
              padding: const EdgeInsets.only(bottom: GlassTokens.spacingMd),
              child: _ModelCard(
                model: model,
                installed: isInstalled,
                selected: selected,
                progress: progress,
                onDownload: () => _download(context, ref, model),
                onCancel: () => ref
                    .read(appleMlDownloadControllerProvider.notifier)
                    .cancel(model),
                onSelect: isInstalled
                    ? () => ref
                        .read(selectedAppleMlModelIdProvider.notifier)
                        .set(model.id)
                    : null,
                onDelete: isInstalled
                    ? () => _confirmDelete(context, ref, model)
                    : null,
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _download(
    BuildContext context,
    WidgetRef ref,
    AppleMlCatalogModel model,
  ) async {
    if (!Platform.isIOS) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Apple ML downloads are iOS-only')),
      );
      return;
    }
    try {
      await ref.read(appleMlDownloadControllerProvider.notifier).download(model);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${model.name} is ready')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    AppleMlCatalogModel model,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${model.name}?'),
        content: const Text(
          'This removes the on-device Core ML files. You can download them again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(appleMlDownloadControllerProvider.notifier).delete(model);
  }
}

class _ModelCard extends StatelessWidget {
  final AppleMlCatalogModel model;
  final bool installed;
  final bool selected;
  final AppleMlDownloadProgress? progress;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback? onSelect;
  final VoidCallback? onDelete;

  const _ModelCard({
    required this.model,
    required this.installed,
    required this.selected,
    required this.progress,
    required this.onDownload,
    required this.onCancel,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final busy = progress != null &&
        (progress!.stage == 'listing' ||
            progress!.stage == 'downloading' ||
            progress!.stage == 'finalizing' ||
            progress!.stage == 'installing');
    return GlassCard(
      borderColor: selected ? AppColors.primary.withValues(alpha: 0.6) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                model.isSdxl ? Icons.auto_awesome : Icons.phone_iphone,
                color: selected ? context.accentText : null,
              ),
              const SizedBox(width: GlassTokens.spacingSm),
              Expanded(
                child: Text(
                  model.name,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected ? context.accentText : null,
                      ),
                ),
              ),
              if (installed)
                const PlatformIcon(
                  material: Icons.check_circle,
                  cupertino: CupertinoIcons.checkmark_circle_fill,
                  color: AppColors.primary,
                  size: 20,
                ),
            ],
          ),
          const SizedBox(height: GlassTokens.spacingSm),
          Text(model.subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            '${model.sizeLabel} · ${model.sizeHint} · iOS ${model.minIosMajor}${model.minIosMinor > 0 ? '.${model.minIosMinor}' : '+'}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          if (busy) ...[
            const SizedBox(height: GlassTokens.spacingMd),
            LinearProgressIndicator(value: progress!.fraction <= 0 ? null : progress!.fraction),
            const SizedBox(height: 6),
            Text(
              progress!.stage == 'listing'
                  ? 'Listing files on Hugging Face…'
                  : progress!.stage == 'installing'
                      ? (progress!.currentFile ??
                          'Installing on the Neural Engine — one time')
                      : '${progress!.fileIndex}/${progress!.fileCount}  ${formatBytes(progress!.receivedBytes)} / ${formatBytes(progress!.totalBytes)}'
                        '${progress!.currentFile == null ? '' : '  ${progress!.currentFile}'}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
          if (progress?.stage == 'error' && progress?.error != null) ...[
            const SizedBox(height: GlassTokens.spacingSm),
            Text(
              progress!.error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                  ),
            ),
          ],
          const SizedBox(height: GlassTokens.spacingMd),
          Wrap(
            spacing: GlassTokens.spacingSm,
            runSpacing: GlassTokens.spacingSm,
            children: [
              if (busy)
                OutlinedButton(
                  onPressed: onCancel,
                  child: const Text('Cancel'),
                )
              else if (!installed)
                FilledButton(
                  onPressed: onDownload,
                  child: const Text('Download'),
                ),
              if (installed && !selected)
                FilledButton(
                  onPressed: onSelect,
                  child: const Text('Use this model'),
                ),
              if (installed && selected)
                const FilledButton(
                  onPressed: null,
                  child: Text('Selected'),
                ),
              if (installed && !busy)
                TextButton(
                  onPressed: onDelete,
                  child: const Text('Delete'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

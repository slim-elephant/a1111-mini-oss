import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';

class ComfyWorkflowDropdown extends ConsumerWidget {
  const ComfyWorkflowDropdown({
    super.key,
    this.dense = true,
    this.includeRefresh = true,
    this.showLabel = true,
  });

  final bool dense;
  final bool includeRefresh;
  final bool showLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workflows = ref.watch(comfyWorkflowsProvider);
    final selected = ref.watch(selectedComfyWorkflowProvider);
    final listingFailed = ref.watch(comfyWorkflowsListingFailedProvider);

    return workflows.when(
      data: (list) {
        if (list.isEmpty) {
          return Row(
            children: [
              const Expanded(
                child: Text(
                  'No workflows available',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              if (includeRefresh)
                IconButton(
                  tooltip: 'Refresh workflows',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _refresh(ref),
                ),
            ],
          );
        }
        final value = list.any((w) => w.path == selected)
            ? selected
            : list.first.path;
        final dropdown = DropdownButtonFormField<String>(
          isExpanded: true,
          value: value,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
          decoration: InputDecoration(
            labelText: showLabel ? 'Workflow' : null,
            isDense: dense,
            border: showLabel ? null : InputBorder.none,
          ),
          items: list
              .map(
                (w) => DropdownMenuItem(
                  value: w.path,
                  child: Text(
                    w.displayName,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              )
              .toList(),
          selectedItemBuilder: (context) => list
              .map(
                (w) => Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    w.displayName,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              )
              .toList(),
          onChanged: (path) {
            if (path != null) {
              ref.read(selectedComfyWorkflowProvider.notifier).set(path);
            }
          },
        );
        final picker = !includeRefresh
            ? dropdown
            : Row(
                children: [
                  Expanded(child: dropdown),
                  IconButton(
                    tooltip: 'Refresh workflows and models',
                    icon: const Icon(Icons.refresh),
                    onPressed: () => _refresh(ref),
                  ),
                ],
              );
        if (!listingFailed) return picker;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            picker,
            Text(
              'Couldn’t load workflows from server — showing built-ins',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(),
      ),
      error: (e, _) => Row(
        children: [
          Expanded(
            child: Text(
              'Could not load workflows: $e',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: 'Retry',
            icon: const Icon(Icons.refresh),
            onPressed: () => _refresh(ref),
          ),
        ],
      ),
    );
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(comfyWorkflowsProvider);
    ref.invalidate(comfyWorkflowDefaultsProvider);
    ref.invalidate(serverModelsProvider);
    ref.invalidate(serverVaesProvider);
    ref.invalidate(serverLorasProvider);
    ref.invalidate(serverSamplersProvider);
    ref.invalidate(serverSchedulersProvider);
  }
}

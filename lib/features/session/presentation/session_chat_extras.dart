import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/glass_tokens.dart';
import '../../../core/api/api_models.dart';
import '../../../core/api/generation_options.dart';
import '../../../core/premium/premium.dart';
import '../../../core/providers/core_providers.dart';

// ════════════════════════════════════════════════════════════════
// LoRA picker sheet
// ════════════════════════════════════════════════════════════════

class LoraPickerSheet extends ConsumerStatefulWidget {
  final List<LoraSelection> initial;
  const LoraPickerSheet({super.key, required this.initial});

  @override
  ConsumerState<LoraPickerSheet> createState() => _LoraPickerSheetState();
}

class _LoraPickerSheetState extends ConsumerState<LoraPickerSheet> {
  late List<LoraSelection> _selected;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _selected = List.of(widget.initial);
  }

  @override
  Widget build(BuildContext context) {
    final loras = ref.watch(serverLorasProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        padding: const EdgeInsets.all(GlassTokens.spacingLg),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Text('LoRAs', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                Text(
                  '${_selected.length} selected',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                IconButton(
                  icon: const Icon(CupertinoIcons.xmark),
                  onPressed: () => Navigator.pop(context, _selected),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Selected weights editor
            if (_selected.isNotEmpty) ...[
              ..._selected.asMap().entries.map((e) {
                final idx = e.key;
                final l = e.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(l.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w500)),
                      ),
                      Expanded(
                        flex: 4,
                        child: Slider(
                          value: l.weight.clamp(-2.0, 2.0),
                          min: -2,
                          max: 2,
                          divisions: 80,
                          label: l.weight.toStringAsFixed(2),
                          onChanged: (v) => setState(() {
                            _selected[idx] = LoraSelection(name: l.name, weight: v);
                          }),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(l.weight.toStringAsFixed(2),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11)),
                      ),
                      IconButton(
                        icon: const Icon(CupertinoIcons.minus_circle, size: 20),
                        color: AppColors.error,
                        onPressed: () => setState(() => _selected.removeAt(idx)),
                      ),
                    ],
                  ),
                );
              }),
              const Divider(),
            ],
            // Search field
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(CupertinoIcons.search, size: 18),
                hintText: 'Filter LoRAs...',
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v.toLowerCase()),
            ),
            const SizedBox(height: 8),
            // List
            Expanded(
              child: loras.when(
                data: (list) {
                  final filtered = list
                      .where((l) =>
                          _filter.isEmpty || l.name.toLowerCase().contains(_filter))
                      .toList();
                  if (filtered.isEmpty) {
                    return Center(
                      child: Text('No LoRAs found',
                          style: Theme.of(context).textTheme.bodyMedium),
                    );
                  }
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final lora = filtered[i];
                      final selected =
                          _selected.any((s) => s.name == lora.name);
                      return ListTile(
                        dense: true,
                        title: Text(lora.name,
                            style: const TextStyle(fontSize: 13)),
                        subtitle: lora.alias != null && lora.alias!.isNotEmpty
                            ? Text(lora.alias!,
                                style: const TextStyle(fontSize: 11))
                            : null,
                        trailing: Icon(
                          selected
                              ? CupertinoIcons.checkmark_circle_fill
                              : CupertinoIcons.add_circled,
                          color: selected
                              ? AppColors.success
                              : AppColors.primary,
                        ),
                        onTap: () {
                          setState(() {
                            if (selected) {
                              _selected.removeWhere((s) => s.name == lora.name);
                            } else {
                              _selected.add(LoraSelection(name: lora.name));
                            }
                          });
                        },
                      );
                    },
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
            SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  child: const Text('Apply'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Prompt styles sheet
// ════════════════════════════════════════════════════════════════

class PromptStylesSheet extends ConsumerStatefulWidget {
  final List<String> initial;
  const PromptStylesSheet({super.key, required this.initial});

  @override
  ConsumerState<PromptStylesSheet> createState() => _PromptStylesSheetState();
}

class _PromptStylesSheetState extends ConsumerState<PromptStylesSheet> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial.toSet();
  }

  @override
  Widget build(BuildContext context) {
    final styles = ref.watch(serverPromptStylesProvider);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        padding: const EdgeInsets.all(GlassTokens.spacingLg),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Text('Prompt Styles',
                    style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                Text('${_selected.length} selected',
                    style: Theme.of(context).textTheme.bodySmall),
                IconButton(
                  icon: const Icon(CupertinoIcons.xmark),
                  onPressed: () =>
                      Navigator.pop(context, _selected.toList()),
                ),
              ],
            ),
            Expanded(
              child: styles.when(
                data: (list) {
                  if (list.isEmpty) {
                    return const Center(
                        child: Text('No prompt styles defined on server'));
                  }
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final s = list[i];
                      final selected = _selected.contains(s.name);
                      return CheckboxListTile(
                        dense: true,
                        title: Text(s.name),
                        subtitle: s.prompt.isNotEmpty
                            ? Text(s.prompt,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11))
                            : null,
                        value: selected,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(s.name);
                          } else {
                            _selected.remove(s.name);
                          }
                        }),
                      );
                    },
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
            SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, _selected.toList()),
                  child: const Text('Apply'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// ControlNet sheet
// ════════════════════════════════════════════════════════════════

class ControlNetSheet extends ConsumerStatefulWidget {
  final List<ControlNetUnit> initial;
  const ControlNetSheet({super.key, required this.initial});

  @override
  ConsumerState<ControlNetSheet> createState() => _ControlNetSheetState();
}

class _ControlNetSheetState extends ConsumerState<ControlNetSheet> {
  late List<ControlNetUnit> _units;

  @override
  void initState() {
    super.initState();
    _units = widget.initial.isEmpty
        ? [const ControlNetUnit(enabled: false)]
        : List.of(widget.initial);
  }

  Future<String?> _pickImageBase64() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (picked == null) return null;
      final bytes = await File(picked.path).readAsBytes();
      return base64Encode(bytes);
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Photo picker is not ready. Fully restart the app once after installing plugin changes.',
            ),
          ),
        );
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final models = ref.watch(controlNetModelsProvider);
    final modules = ref.watch(controlNetModulesProvider);
    final unlimited =
        ref.watch(hasFeatureProvider(PremiumFeature.extraControlNetUnits));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        padding: const EdgeInsets.all(GlassTokens.spacingLg),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Text('ControlNet',
                    style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  icon: const Icon(CupertinoIcons.xmark),
                  onPressed: () => Navigator.pop(context, _units),
                ),
              ],
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: unlimited || kShowLockedFeatures
                    ? _units.length
                    : _units.length.clamp(0, kFreeControlNetUnits),
                itemBuilder: (context, i) {
                  final u = _units[i];
                  final locked = !unlimited && i >= kFreeControlNetUnits;
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('Unit ${i + 1}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              if (locked) ...[
                                const SizedBox(width: 6),
                                const PremiumPill(label: 'PRO'),
                              ],
                              const Spacer(),
                              Switch.adaptive(
                                value: u.enabled,
                                onChanged: locked
                                    ? null
                                    : (v) => setState(() {
                                          _units[i] = u.copyWith(enabled: v);
                                        }),
                              ),
                              if (i > 0)
                                IconButton(
                                  icon: const Icon(CupertinoIcons.trash,
                                      size: 18),
                                  onPressed: () =>
                                      setState(() => _units.removeAt(i)),
                                ),
                            ],
                          ),
                          // Image preview / picker
                          GestureDetector(
                            onTap: locked
                                ? null
                                : () async {
                                    final b64 = await _pickImageBase64();
                                    if (b64 != null) {
                                      setState(() {
                                        _units[i] =
                                            u.copyWith(imageBase64: b64);
                                      });
                                    }
                                  },
                            child: Container(
                              height: 120,
                              decoration: BoxDecoration(
                                color: Colors.black12,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: u.imageBase64 != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.memory(
                                        base64Decode(u.imageBase64!),
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                      ),
                                    )
                                  : const Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(CupertinoIcons.photo, size: 28),
                                          SizedBox(height: 4),
                                          Text('Tap to pick image',
                                              style: TextStyle(fontSize: 12)),
                                        ],
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Module
                          modules.when(
                            data: (list) {
                              if (list.isEmpty) {
                                return _ServerRequiredHint(
                                    label: 'Preprocessor',
                                    message:
                                        'Connect to a server to load preprocessors.');
                              }
                              return DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: list.contains(u.module) ? u.module : null,
                                decoration: const InputDecoration(
                                    labelText: 'Preprocessor'),
                                items: list
                                    .map((m) => DropdownMenuItem(
                                        value: m,
                                        child: Text(m,
                                            overflow: TextOverflow.ellipsis)))
                                    .toList(),
                                onChanged: locked
                                    ? null
                                    : (v) => setState(() => _units[i] =
                                        u.copyWith(module: v ?? 'none')),
                              );
                            },
                            loading: () => const LinearProgressIndicator(),
                            error: (_, __) => _ServerRequiredHint(
                                label: 'Preprocessor',
                                message:
                                    'Connect to a server to load preprocessors.'),
                          ),
                          const SizedBox(height: 8),
                          // Model
                          models.when(
                            data: (list) {
                              if (list.isEmpty) {
                                return _ServerRequiredHint(
                                    label: 'Model',
                                    message:
                                        'Connect to a server to load ControlNet models.');
                              }
                              return DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: list.contains(u.model) ? u.model : null,
                                decoration:
                                    const InputDecoration(labelText: 'Model'),
                                items: list
                                    .map((m) => DropdownMenuItem(
                                        value: m,
                                        child: Text(m,
                                            overflow: TextOverflow.ellipsis)))
                                    .toList(),
                                onChanged: locked
                                    ? null
                                    : (v) => setState(() => _units[i] =
                                        u.copyWith(model: v ?? 'None')),
                              );
                            },
                            loading: () => const LinearProgressIndicator(),
                            error: (_, __) => _ServerRequiredHint(
                                label: 'Model',
                                message:
                                    'Connect to a server to load ControlNet models.'),
                          ),
                          // Weight
                          Row(
                            children: [
                              const Text('Weight'),
                              Expanded(
                                child: Slider(
                                  value: u.weight.clamp(0, 2),
                                  min: 0,
                                  max: 2,
                                  divisions: 40,
                                  label: u.weight.toStringAsFixed(2),
                                  onChanged: locked
                                      ? null
                                      : (v) => setState(() =>
                                          _units[i] = u.copyWith(weight: v)),
                                ),
                              ),
                              SizedBox(
                                  width: 36,
                                  child: Text(u.weight.toStringAsFixed(2),
                                      textAlign: TextAlign.center)),
                            ],
                          ),
                          // Guidance range
                          Row(
                            children: [
                              const Text('Guide'),
                              Expanded(
                                child: RangeSlider(
                                  values: RangeValues(
                                      u.guidanceStart, u.guidanceEnd),
                                  min: 0,
                                  max: 1,
                                  divisions: 20,
                                  labels: RangeLabels(
                                      u.guidanceStart.toStringAsFixed(2),
                                      u.guidanceEnd.toStringAsFixed(2)),
                                  onChanged: locked
                                      ? null
                                      : (v) => setState(() {
                                            _units[i] = u.copyWith(
                                                guidanceStart: v.start,
                                                guidanceEnd: v.end);
                                          }),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Row(
              children: [
                if (unlimited ||
                    kShowLockedFeatures ||
                    _units.length < kFreeControlNetUnits) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(CupertinoIcons.add),
                      label: Text(unlimited || _units.length < kFreeControlNetUnits
                          ? 'Add Unit'
                          : 'Add Unit (Premium)'),
                      onPressed: () async {
                        if (!unlimited && _units.length >= kFreeControlNetUnits) {
                          await requireFeature(context, ref,
                              PremiumFeature.extraControlNetUnits);
                          return;
                        }
                        setState(() => _units
                            .add(const ControlNetUnit(enabled: true)));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _units),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// PNG-info paste sheet (parses generation parameters)
// ════════════════════════════════════════════════════════════════

class PngInfoPasteSheet extends ConsumerStatefulWidget {
  const PngInfoPasteSheet({super.key});

  @override
  ConsumerState<PngInfoPasteSheet> createState() => _PngInfoPasteSheetState();
}

/// Result of parsing PNG-info — applied back to the chat screen state.
class PngInfoApply {
  final String? prompt;
  final String? negativePrompt;
  final int? steps;
  final double? cfgScale;
  final int? width;
  final int? height;
  final int? seed;
  final String? sampler;

  PngInfoApply({
    this.prompt,
    this.negativePrompt,
    this.steps,
    this.cfgScale,
    this.width,
    this.height,
    this.seed,
    this.sampler,
  });
}

class _PngInfoPasteSheetState extends ConsumerState<PngInfoPasteSheet> {
  final _controller = TextEditingController();
  String? _imagePath;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      setState(() {
        _imagePath = picked.path;
        _busy = true;
      });
      final bytes = await File(picked.path).readAsBytes();
      final b64 = base64Encode(bytes);
      final client = ref.read(a1111ClientProvider);
      if (client == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No server connected')),
          );
        }
        return;
      }
      final info = await client.pngInfo(b64);
      _controller.text = info.info.isNotEmpty
          ? info.info
          : (info.parameters['parameters']?.toString() ?? '');
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Photo picker unavailable: ${e.message ?? e.code}. Run a full restart, not hot restart.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to read PNG info: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) _controller.text = data!.text!;
  }

  PngInfoApply _parse(String raw) {
    // A1111 format:
    // <positive>\nNegative prompt: <neg>\nSteps: 20, Sampler: Euler a, CFG scale: 7, Seed: 1234, Size: 512x512, ...
    final lines = raw.split('\n');
    String prompt = '';
    String negative = '';
    String paramsLine = '';
    int phase = 0; // 0 = prompt, 1 = negative, 2 = params
    for (final l in lines) {
      if (l.startsWith('Negative prompt:')) {
        phase = 1;
        negative = l.substring('Negative prompt:'.length).trim();
      } else if (RegExp(r'^[A-Z][A-Za-z ]+: ').hasMatch(l) && phase >= 1) {
        phase = 2;
        paramsLine += (paramsLine.isEmpty ? '' : ', ') + l;
      } else if (phase == 0) {
        prompt += (prompt.isEmpty ? '' : '\n') + l;
      } else if (phase == 1) {
        negative += '\n$l';
      } else {
        paramsLine += ', $l';
      }
    }
    prompt = prompt.trim();
    negative = negative.trim();

    int? parseI(String key) {
      final m = RegExp('$key:\\s*([0-9]+)').firstMatch(paramsLine);
      return m == null ? null : int.tryParse(m.group(1)!);
    }

    double? parseD(String key) {
      final m = RegExp('$key:\\s*([0-9]+(?:\\.[0-9]+)?)').firstMatch(paramsLine);
      return m == null ? null : double.tryParse(m.group(1)!);
    }

    String? parseS(String key) {
      final m = RegExp('$key:\\s*([^,]+)').firstMatch(paramsLine);
      return m?.group(1)?.trim();
    }

    int? width;
    int? height;
    final size = parseS('Size');
    if (size != null) {
      final parts = size.split('x');
      if (parts.length == 2) {
        width = int.tryParse(parts[0].trim());
        height = int.tryParse(parts[1].trim());
      }
    }

    return PngInfoApply(
      prompt: prompt.isEmpty ? null : prompt,
      negativePrompt: negative.isEmpty ? null : negative,
      steps: parseI('Steps'),
      cfgScale: parseD('CFG scale'),
      seed: parseI('Seed'),
      width: width,
      height: height,
      sampler: parseS('Sampler'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.95,
      maxChildSize: 0.98,
      builder: (context, scrollController) => Container(
        padding: const EdgeInsets.fromLTRB(
          GlassTokens.spacingLg,
          GlassTokens.spacingLg + 10,
          GlassTokens.spacingLg,
          GlassTokens.spacingLg,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Text('Import Generation Info',
                    style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  icon: const Icon(CupertinoIcons.xmark),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(CupertinoIcons.photo),
                    label: const Text('From PNG'),
                    onPressed: _busy ? null : _pickImage,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(CupertinoIcons.doc_on_clipboard),
                    label: const Text('Paste'),
                    onPressed: _pasteFromClipboard,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_imagePath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(_imagePath!), height: 120),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                  hintText:
                      'Paste raw generation info here…\n\nExample:\na cat\nNegative prompt: blurry\nSteps: 20, Sampler: Euler a, CFG scale: 7, Seed: 12345, Size: 512x512',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.pop(context, _parse(_controller.text)),
                  child: const Text('Apply to Session'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Hires fix sheet
// ════════════════════════════════════════════════════════════════

class HiresFixSheet extends ConsumerStatefulWidget {
  final HiresFixConfig initial;
  const HiresFixSheet({super.key, required this.initial});

  @override
  ConsumerState<HiresFixSheet> createState() => _HiresFixSheetState();
}

class _HiresFixSheetState extends ConsumerState<HiresFixSheet> {
  late HiresFixConfig _cfg;

  @override
  void initState() {
    super.initState();
    _cfg = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final upscalers = ref.watch(serverUpscalersProvider);
    return Padding(
      padding: EdgeInsets.only(
        left: GlassTokens.spacingLg,
        right: GlassTokens.spacingLg,
        top: GlassTokens.spacingLg,
        bottom: MediaQuery.of(context).viewInsets.bottom + GlassTokens.spacingLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Hires Fix',
                  style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              Switch.adaptive(
                value: _cfg.enabled,
                onChanged: (v) =>
                    setState(() => _cfg = _cfg.copyWith(enabled: v)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          upscalers.when(
            data: (list) {
              if (list.isEmpty) {
                return _ServerRequiredHint(
                    label: 'Upscaler',
                    message:
                        'Connect to a server to load upscalers.');
              }
              return DropdownButtonFormField<String>(
                isExpanded: true,
                value: list.any((u) => u.name == _cfg.upscaler)
                    ? _cfg.upscaler
                    : list.first.name,
                decoration: const InputDecoration(labelText: 'Upscaler'),
                items: list
                    .map((u) => DropdownMenuItem(
                        value: u.name,
                        child:
                            Text(u.name, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: _cfg.enabled
                    ? (v) => setState(
                        () => _cfg = _cfg.copyWith(upscaler: v ?? 'Latent'))
                    : null,
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => _ServerRequiredHint(
                label: 'Upscaler',
                message: 'Connect to a server to load upscalers.'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Text('Scale'),
            Expanded(
              child: Slider(
                value: _cfg.scale.clamp(1, 4),
                min: 1,
                max: 4,
                divisions: 30,
                label: _cfg.scale.toStringAsFixed(2),
                onChanged: _cfg.enabled
                    ? (v) =>
                        setState(() => _cfg = _cfg.copyWith(scale: v))
                    : null,
              ),
            ),
            SizedBox(
                width: 40,
                child: Text(_cfg.scale.toStringAsFixed(2),
                    textAlign: TextAlign.center)),
          ]),
          Row(children: [
            const Text('Denoise'),
            Expanded(
              child: Slider(
                value: _cfg.denoisingStrength.clamp(0, 1),
                min: 0,
                max: 1,
                divisions: 100,
                label: _cfg.denoisingStrength.toStringAsFixed(2),
                onChanged: _cfg.enabled
                    ? (v) => setState(() =>
                        _cfg = _cfg.copyWith(denoisingStrength: v))
                    : null,
              ),
            ),
            SizedBox(
                width: 40,
                child: Text(_cfg.denoisingStrength.toStringAsFixed(2),
                    textAlign: TextAlign.center)),
          ]),
          Row(children: [
            const Text('2nd steps'),
            Expanded(
              child: Slider(
                value: _cfg.steps.toDouble(),
                min: 0,
                max: 60,
                divisions: 60,
                label: '${_cfg.steps}',
                onChanged: _cfg.enabled
                    ? (v) => setState(
                        () => _cfg = _cfg.copyWith(steps: v.round()))
                    : null,
              ),
            ),
            SizedBox(
                width: 40,
                child: Text('${_cfg.steps}', textAlign: TextAlign.center)),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _cfg),
              child: const Text('Apply'),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Extras (upscale) sheet — long-press an image to upscale
// ════════════════════════════════════════════════════════════════

class UpscaleExtrasSheet extends ConsumerStatefulWidget {
  final String imagePath;
  const UpscaleExtrasSheet({super.key, required this.imagePath});

  @override
  ConsumerState<UpscaleExtrasSheet> createState() =>
      _UpscaleExtrasSheetState();
}

class _UpscaleExtrasSheetState extends ConsumerState<UpscaleExtrasSheet> {
  String _upscaler = 'R-ESRGAN 4x+';
  double _scale = 2.0;
  double _faceRestore = 0.0;
  bool _busy = false;
  String? _resultPath;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _resultPath = null;
    });
    try {
      final client = ref.read(a1111ClientProvider);
      if (client == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Upscale needs an active A1111 server')),
          );
        }
        return;
      }
      final bytes = await File(widget.imagePath).readAsBytes();
      final b64 = base64Encode(bytes);
      final res = await client.extraSingle(ExtrasSingleRequest(
        imageBase64: b64,
        upscalingResize: _scale,
        upscaler1: _upscaler,
        gfpganVisibility: _faceRestore,
      ));
      if (res.imageBase64 != null) {
        // Save to temp file for preview
        final tmp = await File(
                '${widget.imagePath}.upscaled-${DateTime.now().millisecondsSinceEpoch}.png')
            .writeAsBytes(base64Decode(res.imageBase64!));
        if (mounted) {
          setState(() => _resultPath = tmp.path);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Saved upscaled image to ${tmp.path}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upscale failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final upscalers = ref.watch(serverUpscalersProvider);
    return Padding(
      padding: EdgeInsets.only(
        left: GlassTokens.spacingLg,
        right: GlassTokens.spacingLg,
        top: GlassTokens.spacingLg,
        bottom: MediaQuery.of(context).viewInsets.bottom + GlassTokens.spacingLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Upscale Image',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          upscalers.when(
            data: (list) => DropdownButtonFormField<String>(
              isExpanded: true,
              value: list.any((u) => u.name == _upscaler)
                  ? _upscaler
                  : (list.isNotEmpty ? list.first.name : _upscaler),
              decoration: const InputDecoration(labelText: 'Upscaler'),
              items: list
                  .map((u) => DropdownMenuItem(
                      value: u.name,
                      child:
                          Text(u.name, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) => setState(() => _upscaler = v ?? _upscaler),
            ),
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          Row(children: [
            const Text('Scale'),
            Expanded(
              child: Slider(
                value: _scale,
                min: 1,
                max: 4,
                divisions: 30,
                label: '${_scale.toStringAsFixed(1)}×',
                onChanged: _busy ? null : (v) => setState(() => _scale = v),
              ),
            ),
            SizedBox(
                width: 40,
                child: Text('${_scale.toStringAsFixed(1)}×',
                    textAlign: TextAlign.center)),
          ]),
          Row(children: [
            const Text('Face fix'),
            Expanded(
              child: Slider(
                value: _faceRestore,
                min: 0,
                max: 1,
                divisions: 20,
                label: _faceRestore.toStringAsFixed(2),
                onChanged:
                    _busy ? null : (v) => setState(() => _faceRestore = v),
              ),
            ),
            SizedBox(
                width: 40,
                child: Text(_faceRestore.toStringAsFixed(2),
                    textAlign: TextAlign.center)),
          ]),
          const SizedBox(height: 8),
          if (_resultPath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(_resultPath!), height: 160),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(CupertinoIcons.arrow_up_right_square),
              label: Text(_busy ? 'Upscaling…' : 'Upscale'),
              onPressed: _busy ? null : _run,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Helper extension on ControlNetUnit
// ════════════════════════════════════════════════════════════════

extension ControlNetUnitCopy on ControlNetUnit {
  ControlNetUnit copyWith({
    bool? enabled,
    String? module,
    String? model,
    String? imageBase64,
    double? weight,
    double? guidanceStart,
    double? guidanceEnd,
  }) =>
      ControlNetUnit(
        enabled: enabled ?? this.enabled,
        module: module ?? this.module,
        model: model ?? this.model,
        imageBase64: imageBase64 ?? this.imageBase64,
        weight: weight ?? this.weight,
        guidanceStart: guidanceStart ?? this.guidanceStart,
        guidanceEnd: guidanceEnd ?? this.guidanceEnd,
        processorRes: processorRes,
        controlMode: controlMode,
        resizeMode: resizeMode,
      );
}

// ════════════════════════════════════════════════════════════════
// Inline hint shown in dropdowns when no server is connected.
// ════════════════════════════════════════════════════════════════

class _ServerRequiredHint extends StatelessWidget {
  final String label;
  final String message;
  const _ServerRequiredHint({required this.label, required this.message});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: [
          Icon(CupertinoIcons.wifi_exclamationmark,
              size: 16, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ),
          TextButton(
            onPressed: () => context.go('/servers'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Connect', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

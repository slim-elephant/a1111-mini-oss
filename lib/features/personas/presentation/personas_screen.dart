import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/glass_tokens.dart';
import '../../../core/models/persona.dart';
import '../../../core/api/api_models.dart';
import '../../../core/api/generation_options.dart';
import '../../../core/providers/core_providers.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/adaptive_scaffold.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../profiles/presentation/profiles_screen.dart';
import '../../session/presentation/session_chat_extras.dart';

final personasProvider = FutureProvider<List<Persona>>((ref) async {
  final db = await ref.read(databaseProvider.future);
  final results = await db.query('personas', orderBy: 'created_at DESC');
  return results.map((e) => Persona.fromMap(e)).toList();
});

class PersonasScreen extends ConsumerWidget {
  const PersonasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personas = ref.watch(personasProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [AppColors.gradientDarkStart, AppColors.gradientDarkEnd]
                : [AppColors.gradientLightStart, AppColors.gradientLightEnd],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
            SliverToBoxAdapter(
              child: ScreenHeader(
                title: 'Profiles',

                actions: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => _showPersonaEditor(context, ref),
                  ),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: GlassTokens.spacingLg),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Saved generation settings you can apply in one tap',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: GlassTokens.spacingLg)),
            personas.when(
              data: (list) {
                if (list.isEmpty) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_outline, size: 64,
                            color: AppColors.primary.withValues(alpha: 0.4)),
                          const SizedBox(height: GlassTokens.spacingLg),
                          Text('No profiles yet', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: GlassTokens.spacingSm),
                          Text('Create one to save your generation presets',
                            style: Theme.of(context).textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: GlassTokens.spacingLg),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _PersonaCard(
                        persona: list[index],
                        onTap: () => _showPersonaEditor(context, ref, persona: list[index]),
                        onDelete: () => _deletePersona(context, ref, list[index]),
                      ),
                      childCount: list.length,
                    ),
                  ),
                );
              },
              loading: () => const SliverToBoxAdapter(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SliverToBoxAdapter(child: Center(child: Text('Error: $e'))),
            ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPersonaEditor(BuildContext context, WidgetRef ref, {Persona? persona}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PersonaEditorScreen(
          persona: persona,
          onSave: (p) async {
            final db = await ref.read(databaseProvider.future);
            if (persona != null) {
              await db.update('personas', p.toMap(), where: 'id = ?', whereArgs: [p.id]);
            } else {
              await db.insert('personas', p.toMap());
            }
            ref.invalidate(personasProvider);
          },
        ),
      ),
    );
  }

  Future<void> _deletePersona(BuildContext context, WidgetRef ref, Persona persona) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Profile'),
        content: Text('Delete "${persona.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final db = await ref.read(databaseProvider.future);
      await db.delete('personas', where: 'id = ?', whereArgs: [persona.id]);
      ref.invalidate(personasProvider);
    }
  }
}

class _PersonaCard extends StatelessWidget {
  final Persona persona;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PersonaCard({
    required this.persona,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: GlassTokens.spacingMd),
      onTap: onTap,
      onLongPress: onDelete,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
                ),
                child: const Icon(Icons.person, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(persona.name, style: Theme.of(context).textTheme.titleSmall),
                    if (persona.description.isNotEmpty)
                      Text(persona.description, style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
          const SizedBox(height: GlassTokens.spacingMd),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (persona.modelName != null)
                StatusBadge(label: persona.modelName!, color: AppColors.primary, icon: Icons.memory),
              StatusBadge(label: persona.samplerName, color: AppColors.success),
              StatusBadge(label: '${persona.steps} steps', color: AppColors.warning),
              StatusBadge(label: 'CFG ${persona.cfgScale}', color: AppColors.primary),
              StatusBadge(label: '${persona.width}×${persona.height}', color: AppColors.primary),
              if (persona.styleNames.isNotEmpty)
                StatusBadge(label: '${persona.styleNames.length} styles', color: AppColors.warning, icon: Icons.auto_awesome),
              if (persona.hiresFix)
                StatusBadge(label: 'Hires ${persona.hiresScale.toStringAsFixed(2)}x', color: AppColors.success, icon: Icons.open_in_full),
              if (persona.controlNetUnits.isNotEmpty)
                StatusBadge(label: 'ControlNet ${persona.controlNetUnits.length}', color: AppColors.accentDark, icon: Icons.bolt),
              if (persona.seed != -1)
                StatusBadge(label: 'Seed: ${persona.seed}', color: AppColors.success, icon: Icons.tag),
              for (final lora in persona.loraConfigs)
                StatusBadge(label: '${lora.name}:${lora.weight}', color: AppColors.accentDark, icon: Icons.extension),
            ],
          ),
        ],
      ),
    );
  }
}

class _PersonaEditorScreen extends ConsumerStatefulWidget {
  final Persona? persona;
  final Future<void> Function(Persona) onSave;

  const _PersonaEditorScreen({this.persona, required this.onSave});

  @override
  ConsumerState<_PersonaEditorScreen> createState() => _PersonaEditorScreenState();
}

class _PersonaEditorScreenState extends ConsumerState<_PersonaEditorScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late final TextEditingController _seedController;
  String? _selectedModel;
  String? _selectedProfile;
  String _samplerName = 'Euler a';
  String? _scheduler;
  int _steps = 20;
  double _cfgScale = 7.0;
  double _distilledCfgScale = 3.5;
  int _width = 512;
  int _height = 512;
  String _vae = 'Automatic';
  int? _clipSkip;
  bool _restoreFaces = false;
  bool _hiresFix = false;
  HiresFixConfig _hiresConfig = const HiresFixConfig();
  List<String> _styleNames = [];
  List<ControlNetUnit> _controlNetUnits = [];
  double _denoisingStrength = 0.7;
  List<LoraConfig> _loraConfigs = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.persona?.name ?? '');
    _descController = TextEditingController(text: widget.persona?.description ?? '');
    _seedController = TextEditingController(text: '${widget.persona?.seed ?? -1}');
    _selectedModel = widget.persona?.modelName;
    _selectedProfile = widget.persona?.profileId;
    _samplerName = widget.persona?.samplerName ?? 'Euler a';
    _scheduler = widget.persona?.scheduler;
    _steps = widget.persona?.steps ?? 20;
    _cfgScale = widget.persona?.cfgScale ?? 7.0;
    _distilledCfgScale = widget.persona?.distilledCfgScale ?? 3.5;
    _width = widget.persona?.width ?? 512;
    _height = widget.persona?.height ?? 512;
    _vae = widget.persona?.vae ?? 'Automatic';
    _clipSkip = widget.persona?.clipSkip;
    _restoreFaces = widget.persona?.restoreFaces ?? false;
    _hiresFix = widget.persona?.hiresFix ?? false;
    _hiresConfig = HiresFixConfig(
      enabled: _hiresFix,
      scale: widget.persona?.hiresScale ?? 1.5,
      steps: widget.persona?.hiresSteps ?? 0,
      denoisingStrength: widget.persona?.hiresDenoising ?? 0.5,
      upscaler: widget.persona?.hiresUpscaler ?? 'Latent',
    );
    _styleNames = List.of(widget.persona?.styleNames ?? const []);
    _controlNetUnits = List.of(widget.persona?.controlNetUnits ?? const []);
    _denoisingStrength = widget.persona?.denoisingStrength ?? 0.7;
    _loraConfigs = List.from(widget.persona?.loraConfigs ?? []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _seedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final models = ref.watch(serverModelsProvider);
    final samplers = ref.watch(serverSamplersProvider);
    final loras = ref.watch(serverLorasProvider);
    final schedulers = ref.watch(serverSchedulersProvider);
    final vaes = ref.watch(serverVaesProvider);
    final profiles = ref.watch(profilesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        title: Text(widget.persona != null ? 'Edit Profile' : 'New Profile'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(GlassTokens.spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Basic info
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Profile name'),
            ),
            const SizedBox(height: GlassTokens.spacingMd),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 2,
            ),
            const SizedBox(height: GlassTokens.spacingXl),

            Text('Style & Feature Bundle', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: GlassTokens.spacingSm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.auto_awesome, size: 16),
                  label: Text(
                    _styleNames.isEmpty
                        ? 'Styles'
                        : 'Styles (${_styleNames.length})',
                  ),
                  onPressed: () async {
                    final selected = await showModalBottomSheet<List<String>>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => PromptStylesSheet(initial: _styleNames),
                    );
                    if (selected != null) {
                      setState(() => _styleNames = selected);
                    }
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.open_in_full, size: 16),
                  label: Text(
                    _hiresConfig.enabled
                        ? 'Hires ${_hiresConfig.scale.toStringAsFixed(2)}x'
                        : 'Hires',
                  ),
                  onPressed: () async {
                    final cfg = await showModalBottomSheet<HiresFixConfig>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => HiresFixSheet(initial: _hiresConfig),
                    );
                    if (cfg != null) {
                      setState(() {
                        _hiresConfig = cfg;
                        _hiresFix = cfg.enabled;
                        _denoisingStrength = cfg.denoisingStrength;
                      });
                    }
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.bolt, size: 16),
                  label: Text(
                    _controlNetUnits.isEmpty
                        ? 'ControlNet'
                        : 'ControlNet (${_controlNetUnits.length})',
                  ),
                  onPressed: () async {
                    final units = await showModalBottomSheet<List<ControlNetUnit>>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) =>
                          ControlNetSheet(initial: _controlNetUnits),
                    );
                    if (units != null) {
                      setState(() {
                        _controlNetUnits = units.where((u) => u.enabled).toList();
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: GlassTokens.spacingMd),

            schedulers.when(
              data: (list) {
                if (list.isEmpty) return const SizedBox.shrink();
                final names = ['Automatic', ...list.map((s) => s.name)];
                return DropdownButtonFormField<String>(
                  value: names.contains(_scheduler ?? 'Automatic')
                      ? (_scheduler ?? 'Automatic')
                      : 'Automatic',
                  decoration: const InputDecoration(labelText: 'Scheduler'),
                  items: names
                      .map((name) => DropdownMenuItem(
                            value: name,
                            child: Text(name),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _scheduler = (v == null || v == 'Automatic') ? null : v;
                  }),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: GlassTokens.spacingMd),

            vaes.when(
              data: (list) {
                final entries = ['Automatic', 'None', ...list.map((v) => v.modelName)];
                return DropdownButtonFormField<String>(
                  value: entries.contains(_vae) ? _vae : 'Automatic',
                  decoration: const InputDecoration(labelText: 'VAE'),
                  items: entries
                      .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                      .toList(),
                  onChanged: (v) => setState(() => _vae = v ?? 'Automatic'),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: GlassTokens.spacingMd),

            Row(
              children: [
                const Text('Distilled CFG'),
                Expanded(
                  child: Slider(
                    value: _distilledCfgScale.clamp(0, 10),
                    min: 0,
                    max: 10,
                    divisions: 100,
                    label: _distilledCfgScale.toStringAsFixed(1),
                    onChanged: (v) => setState(() => _distilledCfgScale = v),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(_distilledCfgScale.toStringAsFixed(1), textAlign: TextAlign.center),
                ),
              ],
            ),

            Row(
              children: [
                const Text('CLIP Skip'),
                const SizedBox(width: 12),
                DropdownButton<int?>(
                  value: _clipSkip,
                  items: const [
                    DropdownMenuItem<int?>(value: null, child: Text('Auto')),
                    DropdownMenuItem<int?>(value: 1, child: Text('1')),
                    DropdownMenuItem<int?>(value: 2, child: Text('2')),
                    DropdownMenuItem<int?>(value: 3, child: Text('3')),
                    DropdownMenuItem<int?>(value: 4, child: Text('4')),
                  ],
                  onChanged: (v) => setState(() => _clipSkip = v),
                ),
              ],
            ),
            const SizedBox(height: GlassTokens.spacingXl),

            // Linked Profile
            Text('Linked style', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: GlassTokens.spacingSm),
            profiles.when(
              data: (list) => DropdownButtonFormField<String>(
                value: _selectedProfile,
                decoration: const InputDecoration(hintText: 'None (optional)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  ...list.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))),
                ],
                onChanged: (v) => setState(() => _selectedProfile = v),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('Could not load profiles'),
            ),
            const SizedBox(height: GlassTokens.spacingXl),

            // Model
            Text('Model', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: GlassTokens.spacingSm),
            models.when(
              data: (list) {
                if (list.isEmpty) {
                  return const InputDecorator(
                    decoration: InputDecoration(labelText: 'Model'),
                    child: Text('Connect to a server to see models'),
                  );
                }
                return DropdownButtonFormField<String>(
                  value: list.any((m) => m.title == _selectedModel) ? _selectedModel : null,
                  decoration: const InputDecoration(hintText: 'Select model'),
                  items: list.map((m) => DropdownMenuItem(
                    value: m.title,
                    child: Text(m.modelName, overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (v) => setState(() => _selectedModel = v),
                  isExpanded: true,
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => TextFormField(
                initialValue: _selectedModel,
                decoration: const InputDecoration(labelText: 'Model name'),
                onChanged: (v) => _selectedModel = v,
              ),
            ),
            const SizedBox(height: GlassTokens.spacingXl),

            // LoRAs
            Row(
              children: [
                Expanded(child: Text('LoRAs', style: Theme.of(context).textTheme.titleSmall)),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  onPressed: () => _addLora(loras),
                ),
              ],
            ),
            if (_loraConfigs.isNotEmpty) ...[
              for (int i = 0; i < _loraConfigs.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: StatusBadge(
                          label: _loraConfigs[i].name,
                          color: AppColors.primary,
                          icon: Icons.extension,
                        ),
                      ),
                      SizedBox(
                        width: 80,
                        child: Slider(
                          value: _loraConfigs[i].weight,
                          min: 0,
                          max: 2.0,
                          divisions: 20,
                          label: _loraConfigs[i].weight.toStringAsFixed(1),
                          onChanged: (v) => setState(() {
                            _loraConfigs[i] = LoraConfig(
                              name: _loraConfigs[i].name,
                              weight: v,
                            );
                          }),
                        ),
                      ),
                      Text(_loraConfigs[i].weight.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 12)),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(() => _loraConfigs.removeAt(i)),
                      ),
                    ],
                  ),
                ),
            ] else
              Text('No LoRAs added', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: GlassTokens.spacingXl),

            // Sampler
            Text('Sampler', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: GlassTokens.spacingSm),
            samplers.when(
              data: (list) => DropdownButtonFormField<String>(
                value: list.any((s) => s.name == _samplerName)
                    ? _samplerName
                    : (list.isNotEmpty ? list.first.name : null),
                items: list.map((s) => DropdownMenuItem(
                  value: s.name,
                  child: Text(s.name),
                )).toList(),
                onChanged: (v) => setState(() => _samplerName = v ?? _samplerName),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => TextFormField(
                initialValue: _samplerName,
                decoration: const InputDecoration(labelText: 'Sampler name'),
                onChanged: (v) => _samplerName = v,
              ),
            ),
            const SizedBox(height: GlassTokens.spacingXl),

            // Steps & CFG
            Row(
              children: [
                const Text('Steps'),
                Expanded(
                  child: Slider(
                    value: _steps.toDouble(),
                    min: 1, max: 150, divisions: 149,
                    label: '$_steps',
                    onChanged: (v) => setState(() => _steps = v.round()),
                  ),
                ),
                SizedBox(width: 36, child: Text('$_steps', textAlign: TextAlign.center)),
              ],
            ),
            Row(
              children: [
                const Text('CFG'),
                Expanded(
                  child: Slider(
                    value: _cfgScale,
                    min: 1, max: 30, divisions: 58,
                    label: _cfgScale.toStringAsFixed(1),
                    onChanged: (v) => setState(() => _cfgScale = v),
                  ),
                ),
                SizedBox(width: 36, child: Text(_cfgScale.toStringAsFixed(1), textAlign: TextAlign.center)),
              ],
            ),
            const SizedBox(height: GlassTokens.spacingMd),

            // Size
            Text('Size', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: GlassTokens.spacingSm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildSizeChip('512×512', 512, 512),
                _buildSizeChip('512×768', 512, 768),
                _buildSizeChip('768×512', 768, 512),
                _buildSizeChip('768×768', 768, 768),
                _buildSizeChip('1024×1024', 1024, 1024),
              ],
            ),
            const SizedBox(height: GlassTokens.spacingXl),

            // Seed
            TextField(
              controller: _seedController,
              decoration: const InputDecoration(
                labelText: 'Seed',
                hintText: '-1 for random',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: GlassTokens.spacingMd),

            // Toggles
            SwitchListTile(
              title: const Text('Restore Faces'),
              value: _restoreFaces,
              onChanged: (v) => setState(() => _restoreFaces = v),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('Hires Fix'),
              value: _hiresFix,
              onChanged: (v) => setState(() => _hiresFix = v),
              contentPadding: EdgeInsets.zero,
            ),
            if (_hiresFix) ...[
              Row(
                children: [
                  const Text('Denoising'),
                  Expanded(
                    child: Slider(
                      value: _denoisingStrength,
                      min: 0, max: 1, divisions: 20,
                      label: _denoisingStrength.toStringAsFixed(2),
                      onChanged: (v) => setState(() => _denoisingStrength = v),
                    ),
                  ),
                  Text(_denoisingStrength.toStringAsFixed(2)),
                ],
              ),
            ],
            const SizedBox(height: GlassTokens.spacingXxl),
          ],
        ),
      ),
    );
  }

  Widget _buildSizeChip(String label, int w, int h) {
    final selected = _width == w && _height == h;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => setState(() { _width = w; _height = h; }),
      visualDensity: VisualDensity.compact,
    );
  }

  void _addLora(AsyncValue<List<SdLora>> lorasAsync) {
    final loras = lorasAsync.valueOrNull ?? [];
    if (loras.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect to a server to browse LoRAs, or enter manually.')),
      );
      _addLoraManually();
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => ListView.builder(
        itemCount: loras.length,
        itemBuilder: (context, index) => ListTile(
          title: Text(loras[index].name),
          subtitle: loras[index].alias != null ? Text(loras[index].alias!) : null,
          onTap: () {
            setState(() {
              _loraConfigs.add(LoraConfig(name: loras[index].name));
            });
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  void _addLoraManually() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add LoRA'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'LoRA filename (without extension)'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      setState(() => _loraConfigs.add(LoraConfig(name: name)));
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final persona = Persona(
      id: widget.persona?.id ?? const Uuid().v4(),
      name: name,
      description: _descController.text.trim(),
      profileId: _selectedProfile,
      modelName: _selectedModel,
      loraConfigs: _loraConfigs,
      styleNames: _styleNames,
      scheduler: _scheduler,
      distilledCfgScale: _distilledCfgScale,
      vae: _vae,
      clipSkip: _clipSkip,
      samplerName: _samplerName,
      steps: _steps,
      cfgScale: _cfgScale,
      seed: int.tryParse(_seedController.text) ?? -1,
      width: _width,
      height: _height,
      restoreFaces: _restoreFaces,
      hiresFix: _hiresConfig.enabled,
      hiresScale: _hiresConfig.scale,
      hiresSteps: _hiresConfig.steps,
      hiresDenoising: _hiresConfig.denoisingStrength,
      hiresUpscaler: _hiresConfig.upscaler,
      controlNetUnits: _controlNetUnits,
      denoisingStrength: _denoisingStrength,
      createdAt: widget.persona?.createdAt ?? DateTime.now(),
    );

    await widget.onSave(persona);
    if (mounted) Navigator.pop(context);
  }
}

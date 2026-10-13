import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/glass_tokens.dart';
import '../../../core/models/ai_profile.dart';
import '../../../core/providers/core_providers.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/adaptive_scaffold.dart';

final profilesProvider = FutureProvider<List<AiProfile>>((ref) async {
  final db = await ref.read(databaseProvider.future);
  final results = await db.query('ai_profiles', orderBy: 'created_at ASC');
  return results.map((e) => AiProfile.fromMap(e)).toList();
});

class ProfilesScreen extends ConsumerWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesProvider);
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
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: ScreenHeader(
                title: 'Styles',

                actions: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => _showProfileEditor(context, ref),
                  ),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: GlassTokens.spacingLg),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Prompt presets for different art styles',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: GlassTokens.spacingLg)),
            profiles.when(
              data: (list) => SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: GlassTokens.spacingLg),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _ProfileCard(
                      profile: list[index],
                      onTap: () => _showProfileEditor(context, ref, profile: list[index]),
                      onDelete: () => _deleteProfile(context, ref, list[index]),
                    ),
                    childCount: list.length,
                  ),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 300,
                    mainAxisExtent: 200,
                    crossAxisSpacing: GlassTokens.spacingMd,
                    mainAxisSpacing: GlassTokens.spacingMd,
                  ),
                ),
              ),
              loading: () => const SliverToBoxAdapter(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SliverToBoxAdapter(
                child: Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showProfileEditor(BuildContext context, WidgetRef ref, {AiProfile? profile}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ProfileEditorSheet(
        profile: profile,
        onSave: (p) async {
          final db = await ref.read(databaseProvider.future);
          if (profile != null) {
            await db.update('ai_profiles', p.toMap(),
                where: 'id = ?', whereArgs: [p.id]);
          } else {
            await db.insert('ai_profiles', p.toMap());
          }
          ref.invalidate(profilesProvider);
        },
      ),
    );
  }

  Future<void> _deleteProfile(BuildContext context, WidgetRef ref, AiProfile profile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Style'),
        content: Text('Delete "${profile.name}"?'),
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
      await db.delete('ai_profiles', where: 'id = ?', whereArgs: [profile.id]);
      ref.invalidate(profilesProvider);
    }
  }
}

class _ProfileCard extends StatelessWidget {
  final AiProfile profile;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ProfileCard({
    required this.profile,
    required this.onTap,
    required this.onDelete,
  });

  IconData get _icon {
    switch (profile.icon) {
      case 'camera': return Icons.camera_alt;
      case 'palette': return Icons.palette;
      case 'brush': return Icons.brush;
      case 'landscape': return Icons.landscape;
      case 'face': return Icons.face;
      default: return Icons.auto_awesome;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(profile.color);

    return GlassCard(
      onTap: onTap,
      onLongPress: onDelete,
      padding: const EdgeInsets.all(GlassTokens.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
                ),
                child: Icon(_icon, color: color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  profile.name,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: GlassTokens.spacingMd),
          if (profile.positivePrompt.isNotEmpty)
            Text(
              profile.positivePrompt,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          const Spacer(),
          if (profile.negativePrompt.isNotEmpty)
            Text(
              'Neg: ${profile.negativePrompt}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

class _ProfileEditorSheet extends StatefulWidget {
  final AiProfile? profile;
  final Future<void> Function(AiProfile) onSave;

  const _ProfileEditorSheet({this.profile, required this.onSave});

  @override
  State<_ProfileEditorSheet> createState() => _ProfileEditorSheetState();
}

class _ProfileEditorSheetState extends State<_ProfileEditorSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _positiveController;
  late final TextEditingController _negativeController;
  String _selectedIcon = 'auto_awesome';
  int _selectedColor = 0xFF3B82F6;

  static const _icons = ['auto_awesome', 'camera', 'palette', 'brush', 'landscape', 'face'];
  static const _colors = [0xFF3B82F6, 0xFF10B981, 0xFFEC4899, 0xFF8B5CF6, 0xFFF59E0B, 0xFFEF4444];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile?.name ?? '');
    _positiveController = TextEditingController(text: widget.profile?.positivePrompt ?? '');
    _negativeController = TextEditingController(text: widget.profile?.negativePrompt ?? '');
    _selectedIcon = widget.profile?.icon ?? 'auto_awesome';
    _selectedColor = widget.profile?.color ?? 0xFF3B82F6;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _positiveController.dispose();
    _negativeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        GlassTokens.spacingLg,
        GlassTokens.spacingLg,
        GlassTokens.spacingLg,
        MediaQuery.of(context).viewInsets.bottom + GlassTokens.spacingLg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.profile != null ? 'Edit Style' : 'New Style',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: GlassTokens.spacingLg),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Style name'),
              autofocus: widget.profile == null,
            ),
            const SizedBox(height: GlassTokens.spacingMd),
            // Icon picker
            Text('Icon', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: _icons.map((icon) {
                final isSelected = icon == _selectedIcon;
                return ChoiceChip(
                  label: Icon(_iconData(icon), size: 18),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _selectedIcon = icon),
                );
              }).toList(),
            ),
            const SizedBox(height: GlassTokens.spacingMd),
            // Color picker
            Text('Color', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: _colors.map((c) {
                final isSelected = c == _selectedColor;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: Colors.white, width: 3)
                          : null,
                      boxShadow: isSelected
                          ? [BoxShadow(color: Color(c).withValues(alpha: 0.4), blurRadius: 8)]
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: GlassTokens.spacingMd),
            TextField(
              controller: _positiveController,
              decoration: const InputDecoration(
                labelText: 'Positive Prompt',
                hintText: 'photorealistic, high quality, 8k...',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: GlassTokens.spacingMd),
            TextField(
              controller: _negativeController,
              decoration: const InputDecoration(
                labelText: 'Negative Prompt',
                hintText: 'low quality, blurry, deformed...',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: GlassTokens.spacingXl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                child: Text(widget.profile != null ? 'Save Changes' : 'Create Style'),
              ),
            ),
            const SizedBox(height: GlassTokens.spacingMd),
          ],
        ),
      ),
    );
  }

  IconData _iconData(String icon) {
    switch (icon) {
      case 'camera': return Icons.camera_alt;
      case 'palette': return Icons.palette;
      case 'brush': return Icons.brush;
      case 'landscape': return Icons.landscape;
      case 'face': return Icons.face;
      default: return Icons.auto_awesome;
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final profile = AiProfile(
      id: widget.profile?.id ?? const Uuid().v4(),
      name: name,
      icon: _selectedIcon,
      color: _selectedColor,
      positivePrompt: _positiveController.text.trim(),
      negativePrompt: _negativeController.text.trim(),
      createdAt: widget.profile?.createdAt ?? DateTime.now(),
    );

    await widget.onSave(profile);
    if (mounted) Navigator.pop(context);
  }
}

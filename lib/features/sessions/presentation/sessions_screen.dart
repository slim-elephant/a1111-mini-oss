import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/session.dart';
import '../../../core/providers/core_providers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/glass_tokens.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/adaptive_scaffold.dart';
import '../../../shared/widgets/platform_icon.dart';
import 'dart:ui';
import '../../../core/utils/image_storage.dart';

// ─── Data ─────────────────────────────────────────────────────────

// sessionsProvider lives in core_providers.dart

/// Fetches the first user prompt for a session (used as subtitle on card).
final sessionFirstPromptProvider =
    FutureProvider.family<String?, String>((ref, sessionId) async {
  final db = await ref.read(databaseProvider.future);
  final rows = await db.query(
    'session_messages',
    columns: ['prompt'],
    where: "session_id = ? AND role = 'user'",
    whereArgs: [sessionId],
    orderBy: 'created_at ASC',
    limit: 1,
  );
  if (rows.isEmpty) return null;
  return rows.first['prompt'] as String?;
});

/// Fetches up to 2 extra image paths for circular thumbnail stack.
/// The parameter is a composite key: 'sessionId|updatedAtMillis'
final sessionExtraImagesProvider =
    FutureProvider.family<List<String>, String>((ref, compositeKey) async {
  final sessionId = compositeKey.split('|')[0];
  final db = await ref.read(databaseProvider.future);
  final rows = await db.query(
    'generated_images',
    columns: ['file_path'],
    where: 'session_id = ?',
    whereArgs: [sessionId],
    orderBy: 'created_at ASC',
    limit: 3, // 1 hero + 2 extra
  );
  if (rows.length <= 1) return [];
  return rows.skip(1).map((r) => r['file_path'] as String).toList();
});

/// Fetches total generated image count for a session.
/// The parameter is a composite key: 'sessionId|updatedAtMillis'
final sessionImageCountProvider =
    FutureProvider.family<int, String>((ref, compositeKey) async {
  final sessionId = compositeKey.split('|')[0];
  final db = await ref.read(databaseProvider.future);
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM generated_images WHERE session_id = ?',
    [sessionId],
  );
  final value = rows.first['c'];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
});

/// Fetches latest model name used in a session.
/// The parameter is a composite key: 'sessionId|updatedAtMillis'
final sessionLatestModelProvider =
    FutureProvider.family<String?, String>((ref, compositeKey) async {
  final sessionId = compositeKey.split('|')[0];
  final db = await ref.read(databaseProvider.future);
  final rows = await db.query(
    'generated_images',
    columns: ['model_name'],
    where: 'session_id = ? AND model_name IS NOT NULL AND model_name != ?',
    whereArgs: [sessionId, ''],
    orderBy: 'created_at DESC',
    limit: 1,
  );
  if (rows.isEmpty) return null;
  return rows.first['model_name'] as String?;
});

// ─── Manage-mode state ────────────────────────────────────────────

final manageModeSessions = StateProvider<bool>((ref) => false);
final selectedSessionIds = StateProvider<Set<String>>((ref) => {});

// ─── Screen ───────────────────────────────────────────────────────

class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSidebar = SidebarMode.of(context);
    final isManaging = ref.watch(manageModeSessions);
    final selected = ref.watch(selectedSessionIds);

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
            // ── App bar area ──
            SliverToBoxAdapter(
              child: Builder(builder: (_) {
                final hasSessions = sessions.maybeWhen(
                  data: (l) => l.isNotEmpty,
                  orElse: () => false,
                );
                return isSidebar
                    ? _SidebarHeader(
                        isManaging: isManaging,
                        hasSelection: selected.isNotEmpty,
                        showManage: hasSessions,
                        onDeleteSelected: () => _deleteSelected(context, ref),
                        onToggleManage: () {
                          ref.read(manageModeSessions.notifier).state = !isManaging;
                          if (isManaging) {
                            ref.read(selectedSessionIds.notifier).state = {};
                          }
                        },
                      )
                    : ScreenHeader(
                        title: 'Sessions',
                        actions: [
                          if (isManaging && selected.isNotEmpty)
                            IconButton(
                              icon: const PlatformIcon(
                                material: Icons.delete_outline,
                                cupertino: CupertinoIcons.trash,
                                color: AppColors.error,
                              ),
                              onPressed: () => _deleteSelected(context, ref),
                            ),
                          if (hasSessions)
                            IconButton(
                              icon: PlatformIcon(
                                material: isManaging ? Icons.close : Icons.checklist_rounded,
                                cupertino:
                                    isManaging ? CupertinoIcons.xmark : CupertinoIcons.checkmark_circle,
                                size: 22,
                              ),
                              tooltip: isManaging ? 'Done' : 'Manage',
                              onPressed: () {
                                ref.read(manageModeSessions.notifier).state = !isManaging;
                                if (isManaging) {
                                  ref.read(selectedSessionIds.notifier).state = {};
                                }
                              },
                            ),
                          IconButton(
                            icon: const PlatformIcon(
                              material: Icons.settings_outlined,
                              cupertino: CupertinoIcons.settings,
                              size: 22,
                            ),
                            tooltip: 'Settings',
                            onPressed: () => context.go('/settings'),
                          ),
                        ],
                      );
              }),
            ),
            sessions.when(
              data: (list) {
                if (list.isEmpty) {
                  return SliverFillRemaining(child: _EmptySessionsView());
                }
                return _SessionsList(sessions: list, compact: isSidebar);
              },
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SliverFillRemaining(
                child: Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSelected(BuildContext context, WidgetRef ref) async {
    final selected = ref.read(selectedSessionIds);
    if (selected.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Sessions'),
        content: Text('Delete ${selected.length} session(s)? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final db = await ref.read(databaseProvider.future);
    for (final id in selected) {
      await db.delete('sessions', where: 'id = ?', whereArgs: [id]);
      await db.delete('session_messages', where: 'session_id = ?', whereArgs: [id]);
      await db.delete('generated_images', where: 'session_id = ?', whereArgs: [id]);
    }
    ref.read(selectedSessionIds.notifier).state = {};
    ref.read(manageModeSessions.notifier).state = false;
    ref.invalidate(sessionsProvider);
  }
}

class _EmptySessionsView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: 0.75,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset(
                'assets/icon/app_icon.png',
                width: 64,
                height: 64,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: GlassTokens.spacingLg),
          Text('No sessions yet', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: GlassTokens.spacingSm),
          Text(
            'Tap + to start generating images',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
          ),
        ],
      ),
    );
  }
}

// ─── Sessions list with date grouping ─────────────────────────────

class _SessionsList extends StatelessWidget {
  final List<Session> sessions;
  final bool compact;

  const _SessionsList({required this.sessions, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final isTablet = !compact && shortestSide >= 700;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final grouped = <DateTime, List<Session>>{};
    for (final session in sessions) {
      final date = DateTime(session.createdAt.year, session.createdAt.month, session.createdAt.day);
      grouped.putIfAbsent(date, () => []).add(session);
    }

    Widget buildHeader(DateTime date) {
      final diff = today.difference(date).inDays;
      String relativeLabel;
      if (diff == 0) {
        relativeLabel = 'Today';
      } else if (diff == 1) {
        relativeLabel = 'Yesterday';
      } else {
        relativeLabel = '$diff days ago';
      }
      final dateLabel = '${date.day}/${date.month}/${date.year}';

      return Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            relativeLabel,
            style: compact
                ? Theme.of(context).textTheme.titleMedium
                : Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(width: 8),
          Text(
            dateLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.textSecondaryDark.withValues(alpha: 0.6)
                      : AppColors.textSecondaryLight.withValues(alpha: 0.6),
                ),
          ),
        ],
      );
    }

    if (isTablet) {
      // Tablet: date headers + 3-column rows of cards
      final items = <Widget>[];
      for (final entry in grouped.entries) {
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          child: buildHeader(entry.key),
        ));
        // Chunk sessions into rows of 3
        for (int i = 0; i < entry.value.length; i += 3) {
          final chunk = entry.value.sublist(i, (i + 3).clamp(0, entry.value.length));
          items.add(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int j = 0; j < 3; j++) ...[
                    if (j > 0) const SizedBox(width: 5),
                    Expanded(
                      child: j < chunk.length
                          ? (chunk[j].thumbnailPath != null
                              ? _ImageSessionCard(session: chunk[j])
                              : _TextSessionCard(session: chunk[j]))
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ));
        }
      }
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => items[index],
          childCount: items.length,
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          int currentIndex = 0;
          for (final entry in grouped.entries) {
            if (currentIndex == index) {
              return Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 12 : 10,
                    compact ? 14 : 12,
                    compact ? 12 : 10,
                    compact ? 6 : 4,
                  ),
                  child: buildHeader(entry.key),
              );
            }
            currentIndex++;
            for (final session in entry.value) {
              if (currentIndex == index) {
                if (session.thumbnailPath != null) {
                  return _ImageSessionCard(session: session);
                }
                return _TextSessionCard(session: session);
              }
              currentIndex++;
            }
          }
          return null;
        },
        childCount: grouped.entries.fold<int>(0, (sum, e) => sum + 1 + e.value.length),
      ),
    );
  }
}

// ─── Rich image card – glassmorphic design ───────────────────────

class _ImageSessionCard extends ConsumerWidget {
  final Session session;
  const _ImageSessionCard({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isManaging = ref.watch(manageModeSessions);
    final selected = ref.watch(selectedSessionIds);
    final isSelected = selected.contains(session.id);
    
    final compositeKey = '${session.id}|${session.updatedAt.millisecondsSinceEpoch}';
    final firstPrompt = ref.watch(sessionFirstPromptProvider(session.id));
    final latestModel = ref.watch(sessionLatestModelProvider(compositeKey));
    final extraImages = ref.watch(sessionExtraImagesProvider(compositeKey));
    final imageCount = ref.watch(sessionImageCountProvider(compositeKey));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: GestureDetector(
        onTap: () {
          if (isManaging) {
            _toggleSelection(ref);
          } else if (SidebarMode.of(context)) {
            ref.read(landscapeDetailSessionProvider.notifier).state = session.id;
          } else {
            context.push('/session/${session.id}');
          }
        },
        onLongPress: isManaging ? null : () => _showSessionOptions(context, ref),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40),
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.45),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.60)),
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.05),
                    blurRadius: 25,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: SizedBox(
                height: 380,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
                  child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Row(
                      children: [
                        if (isManaging) ...[
                          _SelectionCircle(isSelected: isSelected),
                          const SizedBox(width: 12),
                        ] else ...[
                          _CardBrandBadgeTop(isDark: isDark),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Image Generation',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatDate(session.createdAt),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.65)
                                      : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.10)
                                : Colors.white.withValues(alpha: 0.42),
                          ),
                          child: Icon(
                            Icons.arrow_outward_rounded,
                            size: 16,
                            color: isDark ? Colors.white : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(34),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                ImageStorage.resolveFileSync(session.thumbnailPath!),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  color: AppColors.cardDark,
                                  child: const Center(
                                    child: Icon(Icons.image_not_supported, size: 40, color: Colors.white38),
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.transparent,
                                        (isDark ? Colors.black : AppColors.sessionGreen)
                                            .withValues(alpha: isDark ? 0.18 : 0.32),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // ── Thumbnail stack ──
                        extraImages.when(
                          data: (images) {
                            final totalImages = imageCount.valueOrNull ?? 0;
                            if (images.isEmpty && totalImages <= 1) {
                              return const SizedBox.shrink();
                            }
                            final overflow = (totalImages - 1 - images.length).clamp(0, 999);
                            return Positioned(
                              right: 14,
                              top: 18,
                              child: _ThumbnailStack(
                                imagePaths: images,
                                extraCount: overflow,
                              ),
                            );
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const SizedBox.shrink(),
                        ),
                        // ── Bottom info bar – frosted glass over image ──
                        Positioned(
                          bottom: 12,
                          left: 12,
                          right: 12,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(44),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.black.withValues(alpha: 0.36)
                                      : Colors.white.withValues(alpha: 0.42),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : Colors.white.withValues(alpha: 0.40),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    _CardBrandBadge(isDark: isDark, size: 34),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            session.title,
                                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                              fontWeight: FontWeight.w500,
                                              color: isDark ? Colors.white : AppColors.textPrimaryLight,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          latestModel.when(
                                            data: (modelName) => Text(
                                              modelName?.isNotEmpty == true
                                                  ? modelName!
                                                  : (firstPrompt.valueOrNull ?? ''),
                                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                color: isDark
                                                    ? Colors.white.withValues(alpha: 0.72)
                                                    : Colors.black54,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            loading: () => const SizedBox.shrink(),
                                            error: (_, _) => const SizedBox.shrink(),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                ),
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }

  void _toggleSelection(WidgetRef ref) {
    final current = Set<String>.from(ref.read(selectedSessionIds));
    if (current.contains(session.id)) {
      current.remove(session.id);
    } else {
      current.add(session.id);
    }
    ref.read(selectedSessionIds.notifier).state = current;
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return 'Today \u2022 ${date.day} ${_monthName(date.month)}';
    if (d == today.subtract(const Duration(days: 1))) {
      return 'Yesterday \u2022 ${date.day} ${_monthName(date.month)}';
    }
    return '${date.day} ${_monthName(date.month)} ${date.year}';
  }

  String _monthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return months[month - 1];
  }

  void _showSessionOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(context);
                _renameSession(context, ref);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppColors.error),
              title: Text('Delete', style: TextStyle(color: AppColors.error)),
              onTap: () async {
                Navigator.pop(context);
                await _deleteSession(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameSession(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: session.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Session'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Session name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newTitle != null && newTitle.isNotEmpty) {
      final db = await ref.read(databaseProvider.future);
      await db.update('sessions', {'title': newTitle},
          where: 'id = ?', whereArgs: [session.id]);
      ref.invalidate(sessionsProvider);
    }
  }

  Future<void> _deleteSession(BuildContext context, WidgetRef ref) async {
    final db = await ref.read(databaseProvider.future);
    await db.delete('sessions', where: 'id = ?', whereArgs: [session.id]);
    await db.delete('session_messages', where: 'session_id = ?', whereArgs: [session.id]);
    await db.delete('generated_images', where: 'session_id = ?', whereArgs: [session.id]);
    ref.invalidate(sessionsProvider);
  }
}

// ─── Text-only session card (no thumbnail) ───────────────────────

class _TextSessionCard extends ConsumerWidget {
  final Session session;
  const _TextSessionCard({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isManaging = ref.watch(manageModeSessions);
    final selected = ref.watch(selectedSessionIds);
    final isSelected = selected.contains(session.id);
    final firstPrompt = ref.watch(sessionFirstPromptProvider(session.id));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: GlassCard(
        borderColor: isSelected ? AppColors.primary : null,
        onTap: () {
          if (isManaging) {
            _toggleSelection(ref);
          } else if (SidebarMode.of(context)) {
            ref.read(landscapeDetailSessionProvider.notifier).state = session.id;
          } else {
            context.push('/session/${session.id}');
          }
        },
        child: Row(
          children: [
            if (isManaging) ...[
              _SelectionCircle(isSelected: isSelected),
              const SizedBox(width: 12),
            ] else ...[
              _IconCircle(isDark: isDark),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  firstPrompt.when(
                    data: (prompt) => Text(
                      prompt ?? 'No prompt',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    loading: () => const SizedBox(height: 14),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.grey.withValues(alpha: 0.12),
              ),
              child: Icon(
                Icons.arrow_outward_rounded,
                size: 18,
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleSelection(WidgetRef ref) {
    final current = Set<String>.from(ref.read(selectedSessionIds));
    if (current.contains(session.id)) {
      current.remove(session.id);
    } else {
      current.add(session.id);
    }
    ref.read(selectedSessionIds.notifier).state = current;
  }
}

class _SidebarHeader extends StatelessWidget {
  final bool isManaging;
  final bool hasSelection;
  final bool showManage;
  final VoidCallback onDeleteSelected;
  final VoidCallback onToggleManage;

  const _SidebarHeader({
    required this.isManaging,
    required this.hasSelection,
    required this.showManage,
    required this.onDeleteSelected,
    required this.onToggleManage,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Sessions',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          if (isManaging && hasSelection)
            IconButton(
              icon: const PlatformIcon(
                material: Icons.delete_outline,
                cupertino: CupertinoIcons.trash,
                color: AppColors.error,
              ),
              onPressed: onDeleteSelected,
            ),
          if (showManage)
            IconButton(
              icon: PlatformIcon(
                material: isManaging ? Icons.close : Icons.checklist_rounded,
                cupertino: isManaging ? CupertinoIcons.xmark : CupertinoIcons.checkmark_circle,
                size: 20,
              ),
              tooltip: isManaging ? 'Done' : 'Manage',
              onPressed: onToggleManage,
            ),
        ],
      ),
    );
  }
}

// ─── Shared UI atoms ─────────────────────────────────────────────

class _IconCircle extends StatelessWidget {
  final bool isDark;

  const _IconCircle({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.grey.withValues(alpha: 0.14),
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/icon/app_icon.png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _SelectionCircle extends StatelessWidget {
  final bool isSelected;
  const _SelectionCircle({required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected
            ? AppColors.primary
            : Colors.grey.withValues(alpha: 0.15),
        border: isSelected
            ? null
            : Border.all(color: Colors.grey.withValues(alpha: 0.4), width: 1.5),
      ),
      child: isSelected
          ? const Icon(Icons.check, size: 20, color: Colors.white)
          : null,
    );
  }
}

/// Circular thumbnail stack (right side of hero image).
class _ThumbnailStack extends StatelessWidget {
  final List<String> imagePaths;
  final int extraCount;

  const _ThumbnailStack({required this.imagePaths, required this.extraCount});

  @override
  Widget build(BuildContext context) {
    final previewPaths = imagePaths.take(2).toList();
    return Column(
      children: [
        for (final path in previewPaths)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.file(
                  ImageStorage.resolveFileSync(path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.image, size: 18),
                  ),
                ),
              ),
            ),
          ),
        if (extraCount > 0)
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.40),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                '+$extraCount',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimaryDark,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CardBrandBadge extends StatelessWidget {
  final bool isDark;
  final double size;

  const _CardBrandBadge({required this.isDark, this.size = 42});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.88),
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/icon/app_icon.png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _CardBrandBadgeTop extends StatelessWidget {
  final bool isDark;

  const _CardBrandBadgeTop({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.28),
      ),
      child: ClipOval(
        child: Icon(
          Icons.photo_camera_rounded,
          size: 20,
          color: isDark ? Colors.white : Colors.black54,
        ),
      ),
    );
  }
}

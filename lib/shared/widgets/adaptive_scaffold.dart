import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../app/theme/app_colors.dart';
import '../../core/models/generation_backend.dart';
import '../../core/providers/core_providers.dart';
import '../../core/providers/onboarding_prefs.dart';
import '../../core/auth/auth_service.dart';
import '../../core/firebase/firebase_status.dart';
import '../../features/account/presentation/account_sheet.dart';
import '../../features/account/presentation/profile_avatar.dart';
import '../../features/session/presentation/session_chat_screen.dart';
import 'platform_icon.dart';

// Shared anchor for positioning the Feature Request tooltip overlay
// next to the lightbulb nav item.
final _featureRequestLinkProvider = Provider<LayerLink>((_) => LayerLink());
// True while the tooltip overlay is visible — the lightbulb pulses.
final _featureRequestTipShownProvider = StateProvider<bool>((_) => false);

// ─── Sidebar mode marker ──────────────────────────────────────────
/// Placed above [SessionsScreen] when it is rendered as the landscape sidebar.
/// Widgets inside (e.g. session cards) read this to change tap behaviour.
class SidebarMode extends InheritedWidget {
  const SidebarMode({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SidebarMode>() != null;

  @override
  bool updateShouldNotify(SidebarMode _) => false;
}

class _NavItem {
  final String path;
  final IconData materialIcon;
  final IconData materialActiveIcon;
  final IconData cupertinoIcon;
  final IconData cupertinoActiveIcon;
  final String label;

  const _NavItem({
    required this.path,
    required this.materialIcon,
    required this.materialActiveIcon,
    required this.cupertinoIcon,
    required this.cupertinoActiveIcon,
    required this.label,
  });
}

const _topNavItems = [
  _NavItem(
    path: '/sessions',
    materialIcon: Icons.chat_bubble_outline,
    materialActiveIcon: Icons.chat_bubble,
    cupertinoIcon: CupertinoIcons.chat_bubble,
    cupertinoActiveIcon: CupertinoIcons.chat_bubble_fill,
    label: 'Sessions',
  ),
  _NavItem(
    path: '/gallery',
    materialIcon: Icons.photo_library_outlined,
    materialActiveIcon: Icons.photo_library,
    cupertinoIcon: CupertinoIcons.photo,
    cupertinoActiveIcon: CupertinoIcons.photo_fill,
    label: 'Gallery',
  ),
  _NavItem(
    path: '/profiles',
    materialIcon: Icons.auto_awesome_outlined,
    materialActiveIcon: Icons.auto_awesome,
    cupertinoIcon: CupertinoIcons.star,
    cupertinoActiveIcon: CupertinoIcons.star_fill,
    label: 'Styles',
  ),
  _NavItem(
    path: '/personas',
    materialIcon: Icons.person_outline,
    materialActiveIcon: Icons.person,
    cupertinoIcon: CupertinoIcons.person,
    cupertinoActiveIcon: CupertinoIcons.person_fill,
    label: 'Profiles',
  ),
  _NavItem(
    path: '/feature-requests',
    materialIcon: Icons.lightbulb_outline,
    materialActiveIcon: Icons.lightbulb,
    cupertinoIcon: CupertinoIcons.lightbulb,
    cupertinoActiveIcon: CupertinoIcons.lightbulb_fill,
    label: 'Feature Requests',
  ),
];

const _bottomNavItems = [
  _NavItem(
    path: '/servers',
    materialIcon: Icons.dns_outlined,
    materialActiveIcon: Icons.dns,
    cupertinoIcon: CupertinoIcons.cloud,
    cupertinoActiveIcon: CupertinoIcons.cloud_fill,
    label: 'Servers',
  ),
  _NavItem(
    path: '/settings',
    materialIcon: Icons.settings_outlined,
    materialActiveIcon: Icons.settings,
    cupertinoIcon: CupertinoIcons.settings,
    cupertinoActiveIcon: CupertinoIcons.settings,
    label: 'Settings',
  ),
];

const _allNavItems = [..._topNavItems, ..._bottomNavItems];

class AdaptiveScaffold extends ConsumerWidget {
  final Widget child;
  final String currentPath;

  const AdaptiveScaffold({
    super.key,
    required this.child,
    required this.currentPath,
  });

  int get _selectedIndex {
    for (int i = 0; i < _allNavItems.length; i++) {
      if (currentPath.startsWith(_allNavItems[i].path)) return i;
    }
    return 0;
  }

  bool get _isSessionsTab => currentPath.startsWith('/sessions');

  bool _isLandscapeSplit(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Activate split on iPad landscape (width >= 900 for comfortable 3-pane)
    // or any wide-enough landscape device
    return size.width > size.height && size.width >= 900;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final landscapeSplit = _isLandscapeSplit(context);
    final showSplit = landscapeSplit && _isSessionsTab;

    final navRail = _PermanentNavRail(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) => context.go(_allNavItems[index].path),
      showFab: showSplit,
      onFabPressed: showSplit
          ? () {
              final id = const Uuid().v4();
              ref.read(landscapeDetailSessionProvider.notifier).state = id;
            }
          : null,
    );

    Widget body;
    if (showSplit) {
      // ── 3-column layout: nav rail | sessions sidebar | chat detail ──
      body = Row(
        children: [
          navRail,
          // Sessions sidebar
          Container(
            width: 340,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
            ),
            child: SidebarMode(child: child),
          ),
          // Detail pane — selected session chat or empty state
          Expanded(
            child: Consumer(
              builder: (context, ref, _) {
                final sessionId = ref.watch(landscapeDetailSessionProvider);
                if (sessionId == null) {
                  return _LandscapeEmptyDetail(isDark: isDark);
                }
                return SessionChatScreen(
                  key: ValueKey(sessionId),
                  sessionId: sessionId,
                  embeddedInSplit: true,
                );
              },
            ),
          ),
        ],
      );
    } else {
      body = Row(
        children: [
          navRail,
          Expanded(child: child),
        ],
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Stack(
          children: [
            body,
            const _FeatureRequestTipOverlay(),
          ],
        ),
        floatingActionButton: _isSessionsTab && !showSplit
            ? Consumer(
                builder: (context, ref, _) {
                  return FloatingActionButton(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 4,
                    onPressed: () {
                      final backend = ref.read(activeProviderProvider);
                      final canStart = hasUsableGenerationTargetFor(
                        backend,
                        ref.read(activeServerProvider),
                        ref.read(selectedAppleMlModelIdProvider),
                      );
                      if (!canStart) {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(
                              backend == GenerationBackend.appleMl
                                  ? 'No on-device model'
                                  : 'No server set up',
                            ),
                            content: Text(
                              backend == GenerationBackend.appleMl
                                  ? 'Download a Core ML model in Settings to generate on this device.'
                                  : 'Add an A1111 or ComfyUI server in Servers to start generating.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('OK'),
                              ),
                              if (backend == GenerationBackend.appleMl)
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    context.push('/apple-ml-models');
                                  },
                                  child: const Text('Manage models'),
                                ),
                            ],
                          ),
                        );
                        return;
                      }
                      final id = const Uuid().v4();
                      context.push('/session/$id');
                    },
                    child: const PlatformIcon(
                      material: Icons.add,
                      cupertino: CupertinoIcons.add,
                      size: 28,
                    ),
                  );
                },
              )
            : null,
      ),
    );
  }
}

// ─── Empty detail pane ───────────────────────────────────────────

class _LandscapeEmptyDetail extends StatelessWidget {
  final bool isDark;
  const _LandscapeEmptyDetail({required this.isDark});

  @override
  Widget build(BuildContext context) {
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
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: 0.30,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  'assets/icon/app_icon.png',
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Select a session',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'or tap + to start a new one',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark.withValues(alpha: 0.6)
                        : AppColors.textSecondaryLight.withValues(alpha: 0.6),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Permanent nav rail ───────────────────────────────────────────

class _PermanentNavRail extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool showFab;
  final VoidCallback? onFabPressed;

  const _PermanentNavRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.showFab = false,
    this.onFabPressed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCompact =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: 72,
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
            left: false,
            right: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        children: [
                          SizedBox(height: isCompact ? 6 : 12),
                          // Embedded FAB (new session) when in split mode
                          if (showFab) ...[
                            _RailFab(onTap: onFabPressed, isDark: isDark),
                            SizedBox(height: isCompact ? 4 : 8),
                          ],
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/icon/app_icon.png',
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                            ),
                          ),
                          SizedBox(height: isCompact ? 6 : 16),
                          Container(
                            width: 28,
                            height: 0.5,
                            color: isDark
                                ? AppColors.borderDark
                                : AppColors.borderLight,
                          ),
                          SizedBox(height: isCompact ? 4 : 8),
                          for (int i = 0; i < _topNavItems.length; i++)
                            Builder(builder: (context) {
                              final isFeature =
                                  _topNavItems[i].path == '/feature-requests';
                              final btn = _NavButton(
                                item: _topNavItems[i],
                                isSelected: selectedIndex == i,
                                isDark: isDark,
                                compact: isCompact,
                                onTap: () => onDestinationSelected(i),
                                glow: isFeature,
                              );
                              if (!isFeature) return btn;
                              return CompositedTransformTarget(
                                link: ProviderScope.containerOf(context)
                                    .read(_featureRequestLinkProvider),
                                child: btn,
                              );
                            }),
                          const Spacer(),
                          Consumer(
                            builder: (context, ref, _) {
                              final status =
                                  ref.watch(connectionStatusProvider);
                              return Padding(
                                padding: EdgeInsets.symmetric(
                                    vertical: isCompact ? 4 : 8),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => ref
                                      .invalidate(connectionStatusProvider),
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: status.when(
                                    data: (s) => _StatusDot(
                                      color: s.connected
                                          ? AppColors.success
                                          : AppColors.error,
                                      label: s.connected
                                          ? 'Connected'
                                          : (s.error ?? 'Disconnected'),
                                    ),
                                    loading: () => const _StatusDot(
                                        color: AppColors.warning,
                                        label: 'Connecting...'),
                                    error: (_, __) => const _StatusDot(
                                        color: AppColors.error, label: 'Error'),
                                  ),
                                  ),
                                ),
                              );
                            },
                          ),
                          for (int i = 0; i < _bottomNavItems.length; i++)
                            _NavButton(
                              item: _bottomNavItems[i],
                              isSelected:
                                  selectedIndex == _topNavItems.length + i,
                              isDark: isDark,
                              compact: isCompact,
                              onTap: () =>
                                  onDestinationSelected(_topNavItems.length + i),
                            ),
                          if (firebaseReady) ...[
                            SizedBox(height: isCompact ? 4 : 8),
                            Consumer(
                              builder: (context, ref, _) {
                                final user = ref.watch(authUserProvider).valueOrNull;
                                final signedIn =
                                    user != null && !user.isAnonymous;
                                return Tooltip(
                                  message: signedIn ? 'Account' : 'Sign in',
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => showAccountSheet(context),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: ProfileAvatar(
                                        user: user,
                                        size: isCompact ? 30 : 36,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                          SizedBox(height: isCompact ? 6 : 12),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _RailFab extends StatelessWidget {
  final VoidCallback? onTap;
  final bool isDark;

  const _RailFab({required this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'New Chat',
      preferBelow: false,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(CupertinoIcons.add, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _NavButton extends ConsumerWidget {
  final _NavItem item;
  final bool isSelected;
  final bool isDark;
  final bool compact;
  final VoidCallback onTap;
  final bool glow;

  const _NavButton({
    required this.item,
    required this.isSelected,
    required this.isDark,
    this.compact = false,
    required this.onTap,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shouldGlow =
        glow && ref.watch(_featureRequestTipShownProvider);
    final color = shouldGlow
        ? const Color(0xFFFFC107)
        : (isSelected
            ? AppColors.primary
            : (isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight));
    final btnSize = compact ? 40.0 : 48.0;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 1 : 2, horizontal: 10),
      child: Tooltip(
        message: item.label,
        preferBelow: false,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: btnSize,
              height: btnSize,
              decoration: BoxDecoration(
                color: shouldGlow
                    ? const Color(0xFFFFC107).withValues(alpha: 0.18)
                    : (isSelected
                        ? AppColors.primary.withValues(alpha: 0.15)
                        : Colors.transparent),
                borderRadius: BorderRadius.circular(12),
                boxShadow: shouldGlow
                    ? [
                        BoxShadow(
                          color: const Color(0xFFFFC107)
                              .withValues(alpha: 0.55),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: PlatformIcon(
                material: (shouldGlow || isSelected)
                    ? item.materialActiveIcon
                    : item.materialIcon,
                cupertino: (shouldGlow || isSelected)
                    ? item.cupertinoActiveIcon
                    : item.cupertinoIcon,
                color: color,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;
  final String label;

  const _StatusDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
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

class ScreenHeader extends StatelessWidget {
  final String title;
  final bool showBack;
  final List<Widget>? actions;

  const ScreenHeader({
    super.key,
    required this.title,
    this.showBack = false,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
      child: Row(
        children: [
          if (showBack)
            IconButton(
              icon: const PlatformIcon(
                material: Icons.arrow_back_ios_new,
                cupertino: CupertinoIcons.back,
                size: 20,
              ),
              onPressed: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else {
                  context.go('/sessions');
                }
              },
            ),
          if (showBack) const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Feature Request tip overlay — shown after a few minutes of usage
// to point users at the lightbulb icon for feedback/bug reports.
// Dismissible, persisted via OnboardingPrefs.
// ════════════════════════════════════════════════════════════════

class _FeatureRequestTipOverlay extends ConsumerStatefulWidget {
  const _FeatureRequestTipOverlay();

  @override
  ConsumerState<_FeatureRequestTipOverlay> createState() =>
      _FeatureRequestTipOverlayState();
}

class _FeatureRequestTipOverlayState
    extends ConsumerState<_FeatureRequestTipOverlay> {
  static const _delay = Duration(minutes: 3);

  void _setShown(bool v) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cur = ref.read(_featureRequestTipShownProvider);
      if (cur != v) {
        ref.read(_featureRequestTipShownProvider.notifier).state = v;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(onboardingPrefsProvider);
    if (!prefs.ready ||
        prefs.featureRequestTipDismissed ||
        prefs.firstLaunchAt == null) {
      _setShown(false);
      return const SizedBox.shrink();
    }
    final elapsed = DateTime.now().difference(prefs.firstLaunchAt!);
    if (elapsed < _delay) {
      _setShown(false);
      Future.delayed(_delay - elapsed, () {
        if (mounted) setState(() {});
      });
      return const SizedBox.shrink();
    }

    _setShown(true);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final link = ref.read(_featureRequestLinkProvider);

    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: link,
        targetAnchor: Alignment.centerRight,
        followerAnchor: Alignment.centerLeft,
        offset: const Offset(10, 0),
        showWhenUnlinked: false,
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F2230) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFFFFC107).withValues(alpha: 0.55)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb,
                      color: Color(0xFFFFC107), size: 20),
                  const SizedBox(width: 10),
                  const Flexible(
                    child: Text(
                      'Have an idea or hit a bug?\nUse Feature Requests to let us know.',
                      style: TextStyle(fontSize: 12.5, height: 1.35),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                    onPressed: () => ref
                        .read(onboardingPrefsProvider.notifier)
                        .dismissFeatureRequestTip(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

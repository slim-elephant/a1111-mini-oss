import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/sessions/presentation/sessions_screen.dart';
import '../../features/session/presentation/session_chat_screen.dart';
import '../../features/gallery/presentation/gallery_screen.dart';
import '../../features/profiles/presentation/profiles_screen.dart';
import '../../features/personas/presentation/personas_screen.dart';
import '../../features/servers/presentation/servers_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/generation_defaults_screen.dart';
import '../../features/on_device/presentation/apple_ml_models_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/splash/presentation/animated_splash_screen.dart';
import '../../features/feature_requests/presentation/feature_requests_screen.dart';
import '../../core/analytics/app_analytics.dart';
import '../../shared/widgets/adaptive_scaffold.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/splash',
  observers: [AppAnalytics.instance.observer],
  redirect: (context, state) {
    final uri = state.uri;
    if (uri.scheme == 'a1111mini' &&
        (uri.host == 'apple-ml-models' || uri.path == '/apple-ml-models')) {
      return '/apple-ml-models';
    }
    return null;
  },
  routes: [
    // Animated splash (outside shell)
    GoRoute(
      path: '/splash',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const AnimatedSplashScreen(),
    ),

    // Onboarding (outside shell)
    GoRoute(
      path: '/onboarding',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const OnboardingScreen(),
    ),

    // Main shell with navigation rail
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => AdaptiveScaffold(
        currentPath: state.uri.path,
        child: child,
      ),
      routes: [
        GoRoute(
          path: '/sessions',
          builder: (context, state) => const SessionsScreen(),
        ),
        GoRoute(
          path: '/gallery',
          builder: (context, state) => const GalleryScreen(),
        ),
        GoRoute(
          path: '/profiles',
          builder: (context, state) => const ProfilesScreen(),
        ),
        GoRoute(
          path: '/personas',
          builder: (context, state) => const PersonasScreen(),
        ),
        GoRoute(
          path: '/servers',
          builder: (context, state) => const ServersScreen(),
        ),
      ],
    ),

    // Standalone settings (outside shell)
    GoRoute(
      path: '/settings',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const SettingsScreen(),
    ),

    GoRoute(
      path: '/generation-defaults',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const GenerationDefaultsScreen(),
    ),

    GoRoute(
      path: '/apple-ml-models',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const AppleMlModelsScreen(),
    ),

    // Standalone feature requests (outside shell)
    GoRoute(
      path: '/feature-requests',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const FeatureRequestsScreen(),
    ),

    // Session chat (full screen, outside shell)
    GoRoute(
      path: '/session/:id',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => SessionChatScreen(
        sessionId: state.pathParameters['id']!,
      ),
    ),
  ],
);

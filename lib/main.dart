import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'app/router/app_router.dart';
import 'app/theme/app_theme.dart';
import 'core/analytics/app_analytics.dart';
import 'core/auth/auth_service.dart';
import 'core/firebase/firebase_status.dart';
import 'core/on_device/apple_ml_download_platform.dart';
import 'core/on_device/apple_ml_providers.dart';
import 'core/providers/core_providers.dart';
import 'core/security/app_lock.dart';
import 'core/utils/image_storage.dart';
import 'premium/premium_overrides.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppleMlDownloadPlatform.instance.ensureInitialized();

  await initFirebase();

  // Pre-cache documents directory for synchronous path resolution
  await ImageStorage.docsPath;

  if (firebaseReady) {
    // Every user starts anonymous; Account in the nav rail links a real login.
    await AuthService().ensureSignedIn();
    debugPrint('🔑 Firebase UID: ${FirebaseAuth.instance.currentUser?.uid}');

    final analytics = FirebaseAnalytics.instance;
    await analytics.setAnalyticsCollectionEnabled(true);
    await analytics.setUserId(id: FirebaseAuth.instance.currentUser?.uid);
    await analytics.logAppOpen();
  }

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppAnalytics.instance
        .logError('flutter_error', details.exception, details.stack ?? StackTrace.current);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppAnalytics.instance.logError('platform_dispatcher', error, stack);
    return false;
  };

  runApp(
    ProviderScope(
      overrides: premiumOverrides(),
      child: const A1111MiniApp(),
    ),
  );
}

class A1111MiniApp extends ConsumerStatefulWidget {
  const A1111MiniApp({super.key});

  @override
  ConsumerState<A1111MiniApp> createState() => _A1111MiniAppState();
}

class _A1111MiniAppState extends ConsumerState<A1111MiniApp>
    with WidgetsBindingObserver {
  /// Keeps the connection dot honest while the app is open.
  static const _statusPollInterval = Duration(seconds: 45);
  Timer? _statusPoll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startStatusPoll();
  }

  @override
  void dispose() {
    _statusPoll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(authServiceProvider).ensureSignedIn();
      ref.invalidate(connectionStatusProvider);
      _startStatusPoll();
    } else if (state == AppLifecycleState.paused) {
      _statusPoll?.cancel();
    }
  }

  void _startStatusPoll() {
    _statusPoll?.cancel();
    _statusPoll = Timer.periodic(
      _statusPollInterval,
      (_) => ref.invalidate(connectionStatusProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    ref.watch(appleMlDownloadControllerProvider);

    return MaterialApp.router(
      title: 'A1111 Mini',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _resolveThemeMode(themeMode),
      routerConfig: appRouter,
      builder: (context, child) =>
          AppLockGate(child: child ?? const SizedBox.shrink()),
    );
  }

  ThemeMode _resolveThemeMode(String mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}

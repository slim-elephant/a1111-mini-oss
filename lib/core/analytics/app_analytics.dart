import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/widgets.dart';
import '../firebase/firebase_status.dart';

class AppAnalytics {
  AppAnalytics._();

  static final AppAnalytics instance = AppAnalytics._();
  FirebaseAnalytics get analytics => FirebaseAnalytics.instance;

  NavigatorObserver get observer => firebaseReady
      ? FirebaseAnalyticsObserver(analytics: analytics)
      : NavigatorObserver();

  Future<void> logAction(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    try {
      await analytics.logEvent(name: name, parameters: parameters);
    } catch (_) {}
  }

  Future<void> logError(
    String source,
    Object error,
    StackTrace stackTrace,
  ) async {
    try {
      await analytics.logEvent(
        name: 'app_error',
        parameters: {
          'source': source,
          'error': error.toString().substring(0, error.toString().length.clamp(0, 180)),
          'stack': stackTrace.toString().substring(0, stackTrace.toString().length.clamp(0, 220)),
        },
      );
    } catch (_) {}
  }
}

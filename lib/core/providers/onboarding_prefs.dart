import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'core_providers.dart';

class OnboardingPrefs {
  final bool wizardCompleted;
  final bool featureRequestTipDismissed;
  final DateTime? firstLaunchAt;
  final bool ready;

  const OnboardingPrefs({
    required this.wizardCompleted,
    required this.featureRequestTipDismissed,
    required this.firstLaunchAt,
    required this.ready,
  });

  const OnboardingPrefs.empty()
      : wizardCompleted = false,
        featureRequestTipDismissed = false,
        firstLaunchAt = null,
        ready = false;

  OnboardingPrefs copyWith({
    bool? wizardCompleted,
    bool? featureRequestTipDismissed,
    DateTime? firstLaunchAt,
    bool? ready,
  }) =>
      OnboardingPrefs(
        wizardCompleted: wizardCompleted ?? this.wizardCompleted,
        featureRequestTipDismissed:
            featureRequestTipDismissed ?? this.featureRequestTipDismissed,
        firstLaunchAt: firstLaunchAt ?? this.firstLaunchAt,
        ready: ready ?? this.ready,
      );
}

class OnboardingPrefsNotifier extends StateNotifier<OnboardingPrefs> {
  final Ref _ref;
  OnboardingPrefsNotifier(this._ref) : super(const OnboardingPrefs.empty()) {
    _load();
  }

  static const _kWizardKey = 'onboarding_wizard_completed';
  static const _kTipKey = 'feature_request_tip_dismissed';
  static const _kFirstLaunchKey = 'first_launch_at';

  Future<void> _load() async {
    final db = await _ref.read(databaseProvider.future);
    final rows = await db.query('app_settings');
    final map = {for (final r in rows) r['key'] as String: r['value'] as String};

    DateTime? first;
    final firstStr = map[_kFirstLaunchKey];
    if (firstStr != null && firstStr.isNotEmpty) {
      first = DateTime.tryParse(firstStr);
    }
    if (first == null) {
      first = DateTime.now();
      await db.insert(
        'app_settings',
        {'key': _kFirstLaunchKey, 'value': first.toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    state = OnboardingPrefs(
      wizardCompleted: map[_kWizardKey] == 'true',
      featureRequestTipDismissed: map[_kTipKey] == 'true',
      firstLaunchAt: first,
      ready: true,
    );
  }

  Future<void> _set(String key, String value) async {
    final db = await _ref.read(databaseProvider.future);
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> markWizardCompleted() async {
    await _set(_kWizardKey, 'true');
    state = state.copyWith(wizardCompleted: true);
  }

  Future<void> dismissFeatureRequestTip() async {
    await _set(_kTipKey, 'true');
    state = state.copyWith(featureRequestTipDismissed: true);
  }
}

final onboardingPrefsProvider =
    StateNotifierProvider<OnboardingPrefsNotifier, OnboardingPrefs>((ref) {
  return OnboardingPrefsNotifier(ref);
});

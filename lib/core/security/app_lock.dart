import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// ── Storage ─────────────────────────────────────────────────────
const _storage = FlutterSecureStorage();
const _kAppLockEnabledKey = 'app_lock_enabled';

/// ── State ───────────────────────────────────────────────────────
class AppLockState {
  final bool enabled;
  final bool isLocked;
  final bool ready; // initial value loaded from secure storage
  const AppLockState({
    required this.enabled,
    required this.isLocked,
    required this.ready,
  });

  AppLockState copyWith({bool? enabled, bool? isLocked, bool? ready}) =>
      AppLockState(
        enabled: enabled ?? this.enabled,
        isLocked: isLocked ?? this.isLocked,
        ready: ready ?? this.ready,
      );
}

/// Result codes for setEnabled / authenticate flows.
enum AppLockAuthResult {
  /// User authenticated successfully and the change was applied.
  success,

  /// User cancelled the auth prompt.
  cancelled,

  /// Authentication failed (wrong biometric, etc.).
  failed,

  /// Device has no biometrics or device passcode configured.
  notAvailable,
}

class AppLockController extends StateNotifier<AppLockState> {
  AppLockController()
      : super(const AppLockState(enabled: false, isLocked: false, ready: false)) {
    _load();
  }

  final _auth = LocalAuthentication();

  Future<void> _load() async {
    try {
      final v = await _storage.read(key: _kAppLockEnabledKey);
      final enabled = v == 'true';
      state = AppLockState(enabled: enabled, isLocked: enabled, ready: true);
    } catch (_) {
      state = const AppLockState(enabled: false, isLocked: false, ready: true);
    }
  }

  Future<bool> _canAuthenticate() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      // canCheckBiometrics is true if biometrics are enrolled.
      // isDeviceSupported also covers passcode-only devices on iOS.
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Returns true if biometric/passcode succeeded.
  Future<bool> authenticate({String reason = 'Unlock A1111 Mini'}) async {
    final res = await authenticateDetailed(reason: reason);
    return res == AppLockAuthResult.success;
  }

  Future<AppLockAuthResult> authenticateDetailed(
      {String reason = 'Unlock A1111 Mini'}) async {
    if (!await _canAuthenticate()) return AppLockAuthResult.notAvailable;
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      if (ok) {
        state = state.copyWith(isLocked: false);
        return AppLockAuthResult.success;
      }
      return AppLockAuthResult.cancelled;
    } on PlatformException catch (e) {
      // Common error codes: NotAvailable, NotEnrolled, PasscodeNotSet,
      // LockedOut, PermanentlyLockedOut, UserCancel.
      const cancelCodes = {'UserCancel', 'UserFallback', 'SystemCancel'};
      if (cancelCodes.contains(e.code)) return AppLockAuthResult.cancelled;
      const noAuthCodes = {
        'NotAvailable',
        'NotEnrolled',
        'PasscodeNotSet',
        'auth_in_progress',
      };
      if (noAuthCodes.contains(e.code)) return AppLockAuthResult.notAvailable;
      return AppLockAuthResult.failed;
    }
  }

  /// Toggle from Settings UI. Authenticates before enabling/disabling.
  Future<AppLockAuthResult> setEnabledDetailed(bool enable) async {
    final res = await authenticateDetailed(
      reason: enable ? 'Enable App Lock' : 'Disable App Lock',
    );
    if (res != AppLockAuthResult.success) return res;
    await _storage.write(
        key: _kAppLockEnabledKey, value: enable ? 'true' : 'false');
    state = AppLockState(enabled: enable, isLocked: false, ready: true);
    return AppLockAuthResult.success;
  }

  /// Backwards-compatible boolean wrapper.
  Future<bool> setEnabled(bool enable) async =>
      (await setEnabledDetailed(enable)) == AppLockAuthResult.success;

  /// Re-lock when app goes to background.
  void lock() {
    if (state.enabled && !state.isLocked) {
      state = state.copyWith(isLocked: true);
    }
  }
}

final appLockProvider =
    StateNotifierProvider<AppLockController, AppLockState>((ref) {
  return AppLockController();
});

/// ── Lock screen overlay ────────────────────────────────────────
class AppLockGate extends ConsumerStatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Auto-prompt on first load if locked.
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptIfNeeded());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused || s == AppLifecycleState.inactive) {
      ref.read(appLockProvider.notifier).lock();
    } else if (s == AppLifecycleState.resumed) {
      _promptIfNeeded();
    }
  }

  Future<void> _promptIfNeeded() async {
    final st = ref.read(appLockProvider);
    if (st.enabled && st.isLocked) {
      await ref.read(appLockProvider.notifier).authenticate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(appLockProvider);
    final showLock = st.ready && st.enabled && st.isLocked;
    return Stack(
      children: [
        widget.child,
        if (showLock)
          Positioned.fill(
            child: _LockOverlay(
              onUnlock: () =>
                  ref.read(appLockProvider.notifier).authenticate(),
            ),
          ),
      ],
    );
  }
}

class _LockOverlay extends StatelessWidget {
  final Future<bool> Function() onUnlock;
  const _LockOverlay({required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 64),
            const SizedBox(height: 16),
            Text('App Locked',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.fingerprint),
              label: const Text('Unlock'),
              onPressed: () => onUnlock(),
            ),
          ],
        ),
      ),
    );
  }
}

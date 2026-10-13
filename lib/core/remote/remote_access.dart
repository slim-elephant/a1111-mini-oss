import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/server.dart';
import '../premium/entitlements.dart';

/// Reaching a PC away from home (pairing, QR rescans, relay URLs).
/// The open-source build ships without an implementation, so every relay
/// control is hidden there.
abstract class RemoteAccess {
  /// Hint for the Host field, e.g. "https://relay.example.com/s/…".
  String get hostHint;

  /// Pairs with the desktop companion and returns the servers to add.
  Future<List<Server>?> pair(BuildContext context);

  /// Scans a pairing QR for an existing server.
  Future<({String url, String token})?> scanQr(BuildContext context);

  /// Normalises a pasted relay URL, or null if [raw] is not one.
  String? canonicalizeUrl(String raw);

  /// Explains a host/token pair that cannot work, or null if it looks fine.
  String? fieldHint(String host, String token);

  /// Helper text shown under the token field.
  String? tokenHelper(String token);
}

/// Supplied by the premium build.
final remoteAccessProvider = Provider<RemoteAccess?>((ref) => null);

/// Non-null only when the module is present and the user is entitled.
final enabledRemoteAccessProvider = Provider<RemoteAccess?>((ref) {
  final remote = ref.watch(remoteAccessProvider);
  if (remote == null) return null;
  return ref.watch(hasFeatureProvider(PremiumFeature.remoteRelay))
      ? remote
      : null;
});

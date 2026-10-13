import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Features that are locked in the free build. The open-source app only
/// knows these names; a premium build supplies an [Entitlements] that
/// unlocks them.
enum PremiumFeature {
  /// Camera / photo library as an init image (img2img, inpaint).
  imageInput,

  /// Editing ComfyUI workflows in the node graph. Viewing is free.
  comfyGraphEdit,

  /// Reaching your own PC away from home through the Connect relay.
  remoteRelay,

  /// ControlNet units beyond [kFreeControlNetUnits].
  extraControlNetUnits,

  /// Batch sizes above [kFreeMaxBatch].
  largeBatch;

  String get label {
    switch (this) {
      case PremiumFeature.imageInput:
        return 'Editing your own photos';
      case PremiumFeature.comfyGraphEdit:
        return 'Editing ComfyUI workflows';
      case PremiumFeature.remoteRelay:
        return 'Remote access through Connect';
      case PremiumFeature.extraControlNetUnits:
        return 'More than $kFreeControlNetUnits ControlNet units';
      case PremiumFeature.largeBatch:
        return 'Batches larger than $kFreeMaxBatch';
    }
  }
}

const kFreeControlNetUnits = 2;
const kFreeMaxBatch = 2;
const kPremiumMaxBatch = 8;

/// Locked features are hidden rather than shown with a lock until premium
/// launches. Flip to true to show upsell controls again.
const kShowLockedFeatures = false;

abstract class Entitlements {
  const Entitlements();

  bool has(PremiumFeature feature);

  /// Called when the user taps a locked control. A premium build shows its
  /// paywall here.
  Future<void> requestUpgrade(BuildContext context, PremiumFeature feature);
}

/// Default for the open-source build: everything premium stays locked.
class FreeEntitlements extends Entitlements {
  const FreeEntitlements();

  @override
  bool has(PremiumFeature feature) => false;

  @override
  Future<void> requestUpgrade(
    BuildContext context,
    PremiumFeature feature,
  ) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${feature.label} is a Premium feature.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Override in `main` to plug in a different source of entitlements.
final entitlementsProvider =
    Provider<Entitlements>((ref) => const FreeEntitlements());

final hasFeatureProvider = Provider.family<bool, PremiumFeature>(
  (ref, feature) => ref.watch(entitlementsProvider).has(feature),
);

/// Returns true when [feature] is unlocked; otherwise asks the entitlement
/// source to upsell and returns false.
Future<bool> requireFeature(
  BuildContext context,
  WidgetRef ref,
  PremiumFeature feature,
) async {
  final entitlements = ref.read(entitlementsProvider);
  if (entitlements.has(feature)) return true;
  await entitlements.requestUpgrade(context, feature);
  return false;
}

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a1111_mini/core/premium/entitlements.dart';

class _AllUnlocked extends Entitlements {
  const _AllUnlocked();

  @override
  bool has(PremiumFeature feature) => true;

  @override
  Future<void> requestUpgrade(BuildContext context, PremiumFeature f) async {}
}

void main() {
  test('free build locks every premium feature', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    for (final feature in PremiumFeature.values) {
      expect(container.read(hasFeatureProvider(feature)), isFalse);
    }
  });

  test('an override unlocks features', () {
    final container = ProviderContainer(overrides: [
      entitlementsProvider.overrideWithValue(const _AllUnlocked()),
    ]);
    addTearDown(container.dispose);
    expect(
      container.read(hasFeatureProvider(PremiumFeature.remoteRelay)),
      isTrue,
    );
  });
}

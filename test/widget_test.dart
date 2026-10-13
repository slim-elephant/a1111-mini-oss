import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:a1111_mini/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: A1111MiniApp()),
    );
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);

    // Let splash and polling timers run out before teardown.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });
}

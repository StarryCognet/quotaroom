import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quotaroom/ui/widgets/confetti.dart';

void main() {
  testWidgets('confetti burst animates without layout errors', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(child: Stack(children: [ConfettiBurst()])),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
}

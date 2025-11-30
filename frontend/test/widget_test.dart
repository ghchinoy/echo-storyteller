import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/main.dart';

void main() {
  testWidgets('Echo App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const EchoApp());

    // Verify the title is present
    expect(find.text('The Echo Storyteller'), findsOneWidget);

    // Verify the initial status is "Ready" (ignoring the specific Chip structure, just finding text)
    expect(find.text('Ready'), findsOneWidget);

    // Verify the Input Field exists
    expect(find.byType(TextField), findsOneWidget);

    // Verify the Send Button exists
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
  });
}
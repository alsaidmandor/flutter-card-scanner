import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:card_scanner_app/main.dart';

void main() {
  testWidgets('CardScannerApp smoke test and painter verification', (WidgetTester tester) async {
    await tester.pumpWidget(const CardScannerApp());

    // Verify presence of ScanMode chip text
    expect(find.text('ID / Credit Card'), findsOneWidget);
    expect(find.text('A4 Document'), findsOneWidget);

    // Verify CustomPaint is present in widget tree
    expect(find.byType(CustomPaint), findsWidgets);
  });
}

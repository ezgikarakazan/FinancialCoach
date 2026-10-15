import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/upload_screen.dart';

void main() {
  testWidgets('upload form carries setup balance and statement date', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UploadScreen(
          initialInstitutionName: 'Enpara',
          initialStatementDate: DateTime(2026, 8, 3),
          initialOpeningBalance: '12500,50',
        ),
      ),
    );

    final controllers = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((field) => field.controller?.text)
        .toList();
    expect(controllers, contains('Enpara'));
    expect(controllers, contains('12500,50'));
    expect(find.text('Ekstre tarihi: 03.08.2026'), findsOneWidget);
    expect(find.text('Ekstre adı'), findsOneWidget);
  });
}

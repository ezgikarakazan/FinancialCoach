import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/financial_setup_screen.dart';

void main() {
  testWidgets('financial setup presents one field per step with navigation', (
    tester,
  ) async {
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: FinancialSetupScreen(
          onFinished: () async {
            completed = true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .hideCurrentSnackBar();
    await tester.pumpAndSettle();

    expect(find.text('Finansal başlangıç ayarları'), findsOneWidget);
    expect(find.text('Banka / hesap adı'), findsNWidgets(2));
    expect(find.text('Başlangıç bakiyesi (₺)'), findsNothing);
    expect(find.byTooltip('Kurulumu kapat'), findsOneWidget);

    await tester.tap(find.text('Atla'));
    await tester.pumpAndSettle();

    expect(find.text('Başlangıç bakiyesi'), findsOneWidget);
    expect(find.text('Geri dön'), findsOneWidget);
    expect(find.text('Başlangıç bakiyesi (₺)'), findsOneWidget);

    await tester.tap(find.text('Geri dön'));
    await tester.pumpAndSettle();
    expect(find.text('Banka / hesap adı'), findsNWidgets(2));
    expect(completed, isFalse);

    for (var step = 0; step < 3; step++) {
      await tester.tap(find.text('Atla'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Alışveriş limiti'), findsOneWidget);
    expect(find.text('Alışveriş aylık limiti (₺)'), findsOneWidget);
    expect(find.text('Yatırım aylık limiti (₺)'), findsNothing);
    expect(completed, isFalse);
  });

  testWidgets('close button asks for confirmation before finishing', (
    tester,
  ) async {
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: FinancialSetupScreen(
          onFinished: () async {
            completed = true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Kurulumu kapat'));
    await tester.pumpAndSettle();
    expect(find.text('Kurulum kapatılsın mı?'), findsOneWidget);

    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();
    expect(completed, isFalse);

    await tester.tap(find.byTooltip('Kurulumu kapat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
  });
}

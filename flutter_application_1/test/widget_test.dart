// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/screens/profile_screen.dart';

void main() {
  testWidgets('App opens onboarding flow', (WidgetTester tester) async {
    await tester.pumpWidget(
      const FinanceCoachApp(),
    );

    await tester.pumpAndSettle();

    expect(find.text('AI Finance Coach'), findsOneWidget);
  });

  testWidgets('Profile screen shows retry state when user data fetch fails',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilScreen(
          onLogout: () async {},
          userFuture: Future<Map<String, dynamic>>.error(Exception('Network error')),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Profil bilgisi alınamadı'), findsOneWidget);
    expect(find.text('Tekrar Dene'), findsOneWidget);
  });
}

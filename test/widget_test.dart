// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/main.dart';

void main() {
  testWidgets('App renders login screen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const AegisStayApp());

    // Verify that the initial login UI is visible.
    expect(find.text('AegisStay'), findsOneWidget);
    expect(find.text('Login to AegisStay'), findsOneWidget);
  });

  testWidgets('Staff login opens staff dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(const AegisStayApp());

    await tester.tap(find.text('Staff'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Staff ID'), 'staff-7');
    await tester.tap(find.text('Login to AegisStay'));
    await tester.pumpAndSettle();

    expect(find.text('Staff Dashboard'), findsOneWidget);
    expect(find.textContaining('Category:'), findsOneWidget);
  });

  testWidgets('Staff incident overlay appears then navigates on accept', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AegisStayApp());

    await tester.tap(find.text('Staff'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Login to AegisStay'));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.textContaining('URGENT:'), findsOneWidget);
    expect(find.text('ACCEPT & RESPOND'), findsOneWidget);

    await tester.tap(find.text('ACCEPT & RESPOND'));
    await tester.pumpAndSettle();

    expect(find.textContaining('NAVIGATING TO ROOM 302'), findsOneWidget);
    expect(find.text('ROOM CLEARED'), findsOneWidget);
  });
}

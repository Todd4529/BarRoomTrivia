import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bar_rooms_trivia/main.dart';
import 'package:bar_rooms_trivia/auth/auth_page.dart';

void main() {
  testWidgets('MainNavigationHub renders title and target cards', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MainNavigationHub(),
      ),
    );

    expect(find.text('BAR ROOMS TRIVIA'), findsOneWidget);
    expect(find.text('BAR TV DISPLAY'), findsOneWidget);
    expect(find.text('HOST CONTROL PANEL'), findsOneWidget);
  });

  testWidgets('AuthPage renders email, password, and TV navigation components', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AuthPage(),
      ),
    );

    expect(find.text('BAR ROOMS TRIVIA'), findsOneWidget);
    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Password'), findsWidgets);
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text('Sign in with Apple'), findsOneWidget);
    expect(find.text('Next'), findsWidgets);
  });
}

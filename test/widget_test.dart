import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('MainNavigationHub back press shows Exit Application dialog with Yes and Cancel', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MainNavigationHub(),
      ),
    );

    // Simulate back button press via escape shortcut
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Verify dialog appears with 'Exit Application' and 'Yes' / 'Cancel'
    expect(find.text('Exit Application'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('Return to the TV game display or exit the application?'), findsNothing);
    expect(find.text('TV DISPLAY'), findsNothing);

    // Clicking Cancel closes the dialog
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Exit Application'), findsNothing);
    expect(find.text('BAR ROOMS TRIVIA'), findsOneWidget);
  });

  testWidgets('MainNavigationHub exit dialog stays displayed on subsequent back presses until an option is explicitly chosen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MainNavigationHub(),
      ),
    );

    // 1st back press: opens the dialog
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Exit Application'), findsOneWidget);

    // 2nd back press (remote back button / escape): dialog must STAY DISPLAYED
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Exit Application'), findsOneWidget);

    // 3rd escape key press: dialog must still STAY DISPLAYED
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Exit Application'), findsOneWidget);

    // Tapping outside modal barrier: dialog must still STAY DISPLAYED (barrierDismissible is false)
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Exit Application'), findsOneWidget);

    // Only selecting Cancel closes it
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Exit Application'), findsNothing);
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

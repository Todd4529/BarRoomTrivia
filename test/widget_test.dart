// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:bar_rooms_trivia/main.dart';

void main() {
  testWidgets('BarRoomTriviaApp renders navigation hub', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const BarRoomTriviaApp());

    // Verify that our title is rendered.
    expect(find.text('BAR ROOMS TRIVIA'), findsOneWidget);
    expect(find.text('BAR TV DISPLAY'), findsOneWidget);
  });
}

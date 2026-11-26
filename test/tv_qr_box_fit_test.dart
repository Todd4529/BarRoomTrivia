import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bar_rooms_trivia/shared/config/supabase_config.dart';
import 'package:bar_rooms_trivia/shared/services/realtime_service.dart';
import 'package:bar_rooms_trivia/tv/views/tv_display_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'tv_room_code': 'QRFIT'});
    try {
      await SupabaseConfig.initialize();
    } catch (_) {}
  });

  group('Extensive TV Waiting & Ad Signage QR Box Fit Tests', () {
    for (final size in const [
      Size(960, 540),
      Size(1280, 720),
      Size(1920, 1080),
    ]) {
      testWidgets('Flutter TV Lobby Waiting screen QR fits cleanly inside its card at ${size.width.toInt()}x${size.height.toInt()}',
          (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: TvDisplayView(roomCode: 'QRFIT', autoStart: false),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));

        // Ensure zero RenderFlex overflow or uncaught widget exceptions
        expect(tester.takeException(), isNull);

        final qrFinder = find.byType(QrImageView);
        expect(qrFinder, findsOneWidget, reason: 'Waiting lobby screen must render a single QR code');

        final qrRect = tester.getRect(qrFinder);
        expect(qrRect.width, greaterThanOrEqualTo(44.0));
        expect(qrRect.left, greaterThanOrEqualTo(0.0));
        expect(qrRect.top, greaterThanOrEqualTo(0.0));
        expect(qrRect.right, lessThanOrEqualTo(size.width));
        expect(qrRect.bottom, lessThanOrEqualTo(size.height));

        // Clean unmount
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 200));
      });

      testWidgets('Flutter TV Ad Signage Slides 1-3 QR badge fits strictly inside bottom banner box at ${size.width.toInt()}x${size.height.toInt()}',
          (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: TvDisplayView(roomCode: 'QRFIT', autoStart: false),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));

        // Activate Fullscreen Ad Signage Mode with 10s slide duration
        await RealtimeService().broadcastAdModeToggled(
          roomCode: 'QRFIT',
          isAdModeActive: true,
          adSlideDurationSeconds: 10,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 900));

        for (int slideNum = 0; slideNum < 3; slideNum++) {
          expect(tester.takeException(), isNull,
              reason: 'Slide $slideNum must render with zero layout overflow at ${size.width.toInt()}x${size.height.toInt()}');

          final qrFinder = find.byType(QrImageView);
          expect(qrFinder, findsAtLeastNWidgets(1),
              reason: 'Ad Signage slide $slideNum must render QR code inside bottom banner');

          final qrRect = tester.getRect(qrFinder.last);

          // Find the enclosing bottom banner Container (has BorderRadius.circular(16) and Colors.black38)
          final bannerFinder = find.ancestor(
            of: qrFinder.last,
            matching: find.byWidgetPredicate((w) {
              if (w is Container && w.decoration is BoxDecoration) {
                final dec = w.decoration as BoxDecoration;
                return dec.color == Colors.black38 && dec.borderRadius == BorderRadius.circular(16);
              }
              return false;
            }),
          );
          expect(bannerFinder, findsOneWidget,
              reason: 'QR code on Ad Slide $slideNum must live inside the bottom join banner Container');

          final bannerRect = tester.getRect(bannerFinder);
          expect(qrRect.top, greaterThanOrEqualTo(bannerRect.top),
              reason: 'Slide $slideNum QR top (${qrRect.top}) must not overflow banner top (${bannerRect.top})');
          expect(qrRect.bottom, lessThanOrEqualTo(bannerRect.bottom),
              reason: 'Slide $slideNum QR bottom (${qrRect.bottom}) must not overflow banner bottom (${bannerRect.bottom})');
          expect(qrRect.left, greaterThanOrEqualTo(bannerRect.left),
              reason: 'Slide $slideNum QR left (${qrRect.left}) must sit inside banner left (${bannerRect.left})');
          expect(qrRect.right, lessThanOrEqualTo(bannerRect.right),
              reason: 'Slide $slideNum QR right (${qrRect.right}) must not overflow banner right (${bannerRect.right})');

          // Advance to next ad slide and let transition settle completely
          if (slideNum < 2) {
            await tester.pump(const Duration(seconds: 10));
            await tester.pump(const Duration(milliseconds: 900));
          }
        }

        // Clean unmount
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 200));
      });
    }

    test('Web CSS and JS enforce proportional QR box scaling inside ad bottom banner and promo frame', () {
      final css = File('src/style.css').readAsStringSync();
      final js = File('src/main.js').readAsStringSync();

      expect(css.contains('--slide-h: min(100vh, calc(100vw * 9 / 16));'), isTrue);
      expect(css.contains('--slide-w: min(100vw, calc(100vh * 16 / 9));'), isTrue);
      expect(css.contains('max-height: calc(var(--slide-h) * 0.132);'), isTrue);
      expect(css.contains('width: clamp(38px, calc(var(--slide-h) * 0.084), 92px) !important;'), isTrue);
      expect(css.contains('width: 112px !important;'), isTrue);
      expect(js.contains('QRCode.toCanvas(canvasAdCorner, playUrl, { width: 112, margin: 1 }'), isTrue);
      expect(js.contains('QRCode.toCanvas(canvasPromo, playUrl, { width: 112, margin: 1 }'), isTrue);
    });
  });
}

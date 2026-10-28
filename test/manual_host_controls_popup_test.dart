import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Manual Live Host Controls & Pop-up Modal Tests', () {
    test('1. index.html defines #host-manual-modal-overlay with pause and next question buttons', () {
      final html = File('index.html').readAsStringSync();
      expect(html.contains('id="host-manual-modal-overlay"'), isTrue,
          reason: 'index.html must define the host manual modal overlay');
      expect(html.contains('id="btn-manual-modal-pause"'), isTrue,
          reason: 'index.html must define the pause/resume button in the manual pop-up');
      expect(html.contains('id="btn-manual-modal-next-q"'), isTrue,
          reason: 'index.html must define the next question button in the manual pop-up');
      expect(html.contains('id="btn-manual-modal-phase-action"'), isTrue,
          reason: 'index.html must define the primary phase action button in the manual pop-up');
      expect(html.contains('id="btn-open-manual-modal"'), isTrue,
          reason: 'index.html must provide an open console button in the bottom dock');
    });

    test('2. src/style.css defines styling for manual modal and high-contrast buttons', () {
      final css = File('src/style.css').readAsStringSync();
      expect(css.contains('.host-manual-modal-overlay'), isTrue);
      expect(css.contains('.btn-manual-pause'), isTrue);
      expect(css.contains('.btn-manual-next-q'), isTrue);
      expect(css.contains('.btn-manual-phase-action'), isTrue);
      expect(css.contains('.manual-option-correct'), isTrue);
    });

    test('3. src/main.js implements manual pop-up logic and triggers when Manual mode is selected', () {
      final js = File('src/main.js').readAsStringSync();
      expect(js.contains('function openHostManualModal()'), isTrue);
      expect(js.contains('function closeHostManualModal()'), isTrue);
      expect(js.contains('function updateHostManualModalUI()'), isTrue);
      expect(js.contains('function handleManualHostNextQuestionAction()'), isTrue);
      expect(js.contains("if (mode === 'Manual') {\n      openHostManualModal();\n    }"), isTrue,
          reason: 'Selecting Manual mode must immediately open the host manual modal console');
    });

    test('4. lib/host/views/host_dashboard_view.dart defines _showManualHostControlDialog', () {
      final dartCode = File('lib/host/views/host_dashboard_view.dart').readAsStringSync();
      expect(dartCode.contains('void _showManualHostControlDialog(BuildContext context)'), isTrue);
      expect(dartCode.contains('_showManualHostControlDialog(context);'), isTrue,
          reason: 'Tapping Manual mode in game mode chips must launch the modal dialog');
      expect(dartCode.contains('NEXT QUESTION'), isTrue);
      expect(dartCode.contains('PAUSE GAME'), isTrue);
    });
  });
}

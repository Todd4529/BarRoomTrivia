import 'dart:convert';
import 'dart:html' as html;

void postEventImpl(Map<String, dynamic> payload) {
  try {
    final jsonStr = jsonEncode(payload);
    // Setting localStorage fires storage event in ALL other open browser tabs
    html.window.localStorage['bar_rooms_trivia_sync'] = jsonStr;
    // Dispatch local event for current tab
    html.window.dispatchEvent(html.CustomEvent('bar_rooms_trivia_local', detail: jsonStr));
  } catch (_) {}
}

final Set<void Function(Map<String, dynamic> payload)> _listeners = {};
bool _domListenersRegistered = false;

void listenImpl(void Function(Map<String, dynamic> payload) onEvent) {
  _listeners.add(onEvent);
  if (_domListenersRegistered) return;
  _domListenersRegistered = true;

  try {
    html.window.onStorage.listen((event) {
      if (event.key == 'bar_rooms_trivia_sync' && event.newValue != null) {
        try {
          final data = jsonDecode(event.newValue!) as Map<String, dynamic>;
          for (final listener in List.of(_listeners)) {
            listener(data);
          }
        } catch (_) {}
      }
    });

    html.window.addEventListener('bar_rooms_trivia_local', (event) {
      if (event is html.CustomEvent && event.detail != null) {
        try {
          final data = jsonDecode(event.detail.toString()) as Map<String, dynamic>;
          for (final listener in List.of(_listeners)) {
            listener(data);
          }
        } catch (_) {}
      }
    });
  } catch (_) {}
}

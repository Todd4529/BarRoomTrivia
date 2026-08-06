import 'broadcast_sync_stub.dart'
    if (dart.library.html) 'broadcast_sync_web.dart';

class BroadcastSync {
  static void postEvent(Map<String, dynamic> payload) {
    postEventImpl(payload);
  }

  static void listen(void Function(Map<String, dynamic> payload) onEvent) {
    listenImpl(onEvent);
  }
}

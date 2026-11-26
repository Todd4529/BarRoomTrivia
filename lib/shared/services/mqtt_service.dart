import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;
  MqttService._internal();

  MqttServerClient? _client;
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  final Set<String> _subscribedTopics = {};
  final List<Map<String, dynamic>> _pendingPublishes = [];
  final StreamController<Map<String, dynamic>> _eventController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;

  Timer? _reconnectTimer;
  bool _isConnecting = false;

  Future<void> connect() async {
    if (kIsWeb) return; // MqttServerClient requires dart:io TCP sockets
    if (_isConnected || _isConnecting) return;
    _isConnecting = true;

    try {
      final rand = Random().nextInt(100000);
      final clientId = 'flutter_tv_${DateTime.now().millisecondsSinceEpoch}_$rand';

      _client = MqttServerClient('broker.emqx.io', clientId);
      _client!.port = 1883;
      _client!.logging(on: false);
      _client!.keepAlivePeriod = 30;
      _client!.autoReconnect = true;

      _client!.onDisconnected = () {
        debugPrint('[MQTT] Disconnected from broker.emqx.io');
        _isConnected = false;
        _scheduleReconnect();
      };

      _client!.onConnected = () {
        debugPrint('[MQTT] Connected to broker.emqx.io:1883');
        _isConnected = true;
        _isConnecting = false;
        for (final topic in _subscribedTopics) {
          _client!.subscribe(topic, MqttQos.atMostOnce);
        }
        _flushPendingPublishes();
      };

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(MqttQos.atMostOnce);

      _client!.connectionMessage = connMessage;

      final status = await _client!.connect();
      if (status?.state == MqttConnectionState.connected) {
        _isConnected = true;
        _listenToUpdates();
        _flushPendingPublishes();
      } else {
        _isConnected = false;
        _scheduleReconnect();
      }
    } catch (e) {
      debugPrint('[MQTT] Connection failed: $e');
      _isConnected = false;
      _scheduleReconnect();
    } finally {
      _isConnecting = false;
    }
  }

  void _flushPendingPublishes() {
    if (!_isConnected || _client == null || _pendingPublishes.isEmpty) return;
    final queued = List<Map<String, dynamic>>.from(_pendingPublishes);
    _pendingPublishes.clear();
    for (final item in queued) {
      publish(item['topic'] as String, item['payload'] as Map<String, dynamic>);
    }
  }

  void _listenToUpdates() {
    _client?.updates?.listen((List<MqttReceivedMessage<MqttMessage?>>? messages) {
      if (messages == null || messages.isEmpty) return;
      for (final message in messages) {
        try {
          final recMess = message.payload as MqttPublishMessage;
          final pt = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
          final json = jsonDecode(pt) as Map<String, dynamic>;
          _eventController.add(json);
        } catch (e) {
          debugPrint('[MQTT] Error parsing incoming message: $e');
        }
      }
    });
  }

  void subscribeToRoom(String roomCode) {
    final norm = roomCode.toUpperCase().trim();
    if (norm.isEmpty) return;
    subscribeTopic('barrooms_trivia/room_$norm');
    final stripped = norm.replaceAll('-', '');
    if (stripped != norm) {
      subscribeTopic('barrooms_trivia/room_$stripped');
    }
  }

  void unsubscribeFromRoom(String roomCode) {
    final norm = roomCode.toUpperCase().trim();
    if (norm.isEmpty) return;
    unsubscribeTopic('barrooms_trivia/room_$norm');
    final stripped = norm.replaceAll('-', '');
    if (stripped != norm) {
      unsubscribeTopic('barrooms_trivia/room_$stripped');
    }
  }

  void subscribeTopic(String topic) {
    _subscribedTopics.add(topic);
    if (_isConnected && _client != null) {
      _client!.subscribe(topic, MqttQos.atMostOnce);
      debugPrint('[MQTT] Subscribed to topic: $topic');
    }
  }

  void unsubscribeTopic(String topic) {
    _subscribedTopics.remove(topic);
    if (_isConnected && _client != null) {
      try {
        _client!.unsubscribe(topic);
      } catch (_) {}
    }
    _disconnectIfIdle();
  }

  void _disconnectIfIdle() {
    if (_subscribedTopics.isNotEmpty) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pendingPublishes.clear();
    if (_client != null) {
      try {
        _client!.onDisconnected = null;
        _client!.autoReconnect = false;
        _client!.disconnect();
      } catch (_) {}
      _client = null;
    }
    _isConnected = false;
    _isConnecting = false;
  }

  void publish(String topic, Map<String, dynamic> payload) {
    if (kIsWeb) return;
    if (!_isConnected || _client == null) {
      _pendingPublishes.add({'topic': topic, 'payload': payload});
      if (_pendingPublishes.length > 30) {
        _pendingPublishes.removeAt(0);
      }
      connect();
      return;
    }
    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonEncode(payload));
      _client!.publishMessage(topic, MqttQos.atMostOnce, builder.payload!);
    } catch (e) {
      debugPrint('[MQTT] Error publishing to $topic: $e');
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!_isConnected) {
        connect();
      }
    });
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscribedTopics.clear();
    _pendingPublishes.clear();
    _client?.onDisconnected = null;
    _client?.autoReconnect = false;
    _client?.disconnect();
    _client = null;
    _isConnected = false;
    _isConnecting = false;
  }
}

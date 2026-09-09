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
  final StreamController<Map<String, dynamic>> _eventController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;

  Timer? _reconnectTimer;
  bool _isConnecting = false;

  Future<void> connect() async {
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
        // Resubscribe to all desired topics
        for (final topic in _subscribedTopics) {
          _client!.subscribe(topic, MqttQos.atMostOnce);
        }
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

  void _listenToUpdates() {
    _client?.updates?.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
      if (c == null || c.isEmpty) return;
      try {
        final recMess = c[0].payload as MqttPublishMessage;
        final pt = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        final json = jsonDecode(pt) as Map<String, dynamic>;
        _eventController.add(json);
      } catch (e) {
        debugPrint('[MQTT] Error parsing incoming message: $e');
      }
    });
  }

  void subscribeToRoom(String roomCode) {
    final norm = roomCode.toUpperCase().trim();
    subscribeTopic('barrooms_trivia/room_$norm');
    if (norm != 'TRIV') {
      subscribeTopic('barrooms_trivia/room_TRIV');
    }
    subscribeTopic('tv_pairing');
  }

  void subscribeTopic(String topic) {
    _subscribedTopics.add(topic);
    if (_isConnected && _client != null) {
      _client!.subscribe(topic, MqttQos.atMostOnce);
      debugPrint('[MQTT] Subscribed to topic: $topic');
    }
  }

  void publish(String topic, Map<String, dynamic> payload) {
    if (!_isConnected || _client == null) return;
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
    _client?.disconnect();
    _isConnected = false;
  }
}

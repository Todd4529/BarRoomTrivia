import 'package:flutter/services.dart';

const MethodChannel _nativeChannel = MethodChannel('com.barroomstrivia/audio');

Future<void> terminateApp() async {
  try {
    await _nativeChannel.invokeMethod('exitApp');
  } catch (_) {}

  try {
    await SystemNavigator.pop(animated: true);
  } catch (_) {}
}

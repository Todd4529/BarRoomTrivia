import 'package:flutter/services.dart';

const MethodChannel _nativeChannel = MethodChannel('com.barroomstrivia/audio');

void terminateApp() {
  try {
    _nativeChannel.invokeMethod('exitApp');
  } catch (_) {}

  try {
    SystemNavigator.pop();
  } catch (_) {}
}

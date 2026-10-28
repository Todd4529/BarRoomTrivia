import 'dart:io' as io;
import 'package:flutter/services.dart';

const MethodChannel _nativeChannel = MethodChannel('com.barroomstrivia/audio');

void terminateApp() {
  try {
    _nativeChannel.invokeMethod('exitApp');
  } catch (_) {}

  try {
    SystemNavigator.pop();
  } catch (_) {}

  if (!io.Platform.environment.containsKey('FLUTTER_TEST')) {
    try {
      io.exit(0);
    } catch (_) {}
  }
}

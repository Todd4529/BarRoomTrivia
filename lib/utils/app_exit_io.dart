import 'dart:io' as io;
import 'package:flutter/services.dart';

const MethodChannel _nativeChannel = MethodChannel('com.barroomstrivia/audio');

Future<void> terminateApp() async {
  if (io.Platform.environment.containsKey('FLUTTER_TEST')) {
    try {
      await _nativeChannel.invokeMethod('exitApp');
    } catch (_) {}
    try {
      await SystemNavigator.pop();
    } catch (_) {}
    return;
  }

  try {
    await _nativeChannel
        .invokeMethod('exitApp')
        .timeout(const Duration(milliseconds: 300));
  } catch (_) {}

  try {
    await SystemNavigator.pop(animated: true);
  } catch (_) {}

  if (io.Platform.isWindows || io.Platform.isLinux || io.Platform.isMacOS) {
    try {
      io.exit(0);
    } catch (_) {}
  } else {
    // Allow Android/iOS Activity finish lifecycle (moveTaskToBack + finishAndRemoveTask)
    // to complete before hard process termination so OS does not respawn the Activity.
    await Future.delayed(const Duration(milliseconds: 350));
    try {
      io.exit(0);
    } catch (_) {}
  }
}

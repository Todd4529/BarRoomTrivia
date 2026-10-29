import 'app_exit_stub.dart'
    if (dart.library.io) 'app_exit_io.dart'
    if (dart.library.html) 'app_exit_web.dart';

void exitApplication() {
  terminateApp();
}

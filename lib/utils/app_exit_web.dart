// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'package:flutter/services.dart';

Future<void> terminateApp() async {
  try {
    if (html.document.fullscreenElement != null) {
      html.document.exitFullscreen();
    }
  } catch (_) {}

  try {
    await SystemNavigator.pop(animated: true);
  } catch (_) {}

  try {
    html.window.close();
  } catch (_) {}

  try {
    html.window.open('', '_self').close();
  } catch (_) {}

  // Fallback for browsers that disallow window.close() on user-opened tabs
  try {
    final body = html.document.body;
    if (body != null) {
      body.setInnerHtml(
        '''
        <div style="display:flex;flex-direction:column;align-items:center;justify-content:center;height:100vh;width:100vw;background:#0a0b10;color:#fff;text-align:center;font-family:sans-serif;padding:24px;box-sizing:border-box;position:fixed;top:0;left:0;z-index:99999;">
          <div style="background:#141824;border:2px solid rgba(255,255,255,0.2);border-radius:24px;padding:36px 28px;max-width:460px;width:100%;">
            <div style="font-size:54px;margin-bottom:14px;">👋</div>
            <h2 style="font-size:24px;font-weight:900;color:#fff;letter-spacing:1px;margin:0 0 10px 0;">APPLICATION CLOSED</h2>
            <p style="color:rgba(255,255,255,0.7);font-size:14px;line-height:1.5;margin:0 0 24px 0;">
              Bar Rooms Trivia has ended and disconnected.<br>
              You may now safely close this browser window or press the Home button on your remote.
            </p>
            <button onclick="window.location.reload()" style="width:100%;background:#00e5ff;color:#000;font-weight:900;border:none;padding:14px 24px;border-radius:14px;font-size:15px;cursor:pointer;">
              🔄 Re-open Bar Rooms Trivia
            </button>
          </div>
        </div>
        ''',
        treeSanitizer: html.NodeTreeSanitizer.trusted,
      );
    }
  } catch (_) {}
}

import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Enter browser fullscreen (hides Chrome URL bar on Android).
void requestBrowserFullscreen() {
  final doc = web.document.documentElement;
  if (doc == null) return;
  if (web.document.fullscreenElement != null) return;

  doc.requestFullscreen().toDart.then((_) {}, onError: (_, [__]) {});
}

bool get isBrowserFullscreen => web.document.fullscreenElement != null;

/// Lock the browser / device to landscape when the API allows it
/// (Android Chrome after a user gesture / fullscreen; no-op where unsupported).
void lockLandscapeOrientation() {
  try {
    final orientation = web.window.screen.orientation;
    // Values: any, natural, landscape, portrait, landscape-primary, ...
    orientation.lock('landscape').toDart.then((_) {}, onError: (_, [__]) {});
  } catch (_) {
    // iOS / desktop: Screen Orientation lock is often unavailable.
  }
}

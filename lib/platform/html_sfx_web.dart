import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Lightweight SFX via a **single reused** [HTMLAudioElement].
///
/// Creating a new element on every jump was leaking media nodes and caused
/// long-session hitching on mobile/desktop Chrome. Restarting one element is
/// enough for short one-shot SFX and stays unlock-safe after [unlock].
class HtmlSfx {
  HtmlSfx(this.url, {this.volume = 1.0});

  final String url;
  final double volume;

  web.HTMLAudioElement? _el;

  void preload() {
    final el = web.HTMLAudioElement()
      ..src = url
      ..preload = 'auto'
      ..volume = volume;
    _el = el;
  }

  /// Warm playback inside a user gesture (autoplay policy).
  Future<void> unlock() async {
    final el = _el;
    if (el == null) return;
    final wasMuted = el.muted;
    el.muted = true;
    try {
      await el.play().toDart;
      el.pause();
      el.currentTime = 0;
    } catch (_) {
      // Retry on a later gesture.
    } finally {
      el.muted = wasMuted;
    }
  }

  void play() {
    final el = _el;
    if (el == null) return;
    try {
      el.muted = false;
      el.volume = volume;
      el.currentTime = 0;
      el.play().toDart.then((_) {}, onError: (_, [__]) {});
    } catch (_) {}
  }

  void stop() {
    final el = _el;
    if (el == null) return;
    try {
      el.pause();
      el.currentTime = 0;
    } catch (_) {}
  }
}

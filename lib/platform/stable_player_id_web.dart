import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Keys must match `web/index.html` `__auntyStore` bootstrap.
const _playerKey = 'aunty_stable_player_id';
const _totalKey = 'aunty_cached_total_score';

/// Native JS bridge installed by index.html (most reliable on Flutter web).
@JS('__auntyStore')
external JSAuntyStore? get _auntyStore;

extension type JSAuntyStore._(JSObject _) implements JSObject {
  external String getPlayerId();
  external void setPlayerId(String id);
  external String getTotal();
  external void setTotal(String total);
}

/// Survives F5 / PWA relaunch on the **same origin**.
String? readStablePlayerId() {
  try {
    final bridge = _auntyStore;
    if (bridge != null) {
      final v = bridge.getPlayerId().trim();
      if (v.isNotEmpty) return v;
    }
  } catch (_) {}

  try {
    final v = web.window.localStorage.getItem(_playerKey);
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  } catch (_) {
    return null;
  }
}

void writeStablePlayerId(String id) {
  final trimmed = id.trim();
  if (trimmed.isEmpty) return;

  try {
    _auntyStore?.setPlayerId(trimmed);
  } catch (_) {}

  try {
    web.window.localStorage.setItem(_playerKey, trimmed);
  } catch (_) {}
}

/// Last known Firestore total — instant HUD after refresh before network returns.
int? readCachedTotalScore() {
  try {
    final bridge = _auntyStore;
    if (bridge != null) {
      final raw = bridge.getTotal().trim();
      if (raw.isNotEmpty) {
        final n = int.tryParse(raw);
        if (n != null) return n;
      }
    }
  } catch (_) {}

  try {
    final v = web.window.localStorage.getItem(_totalKey);
    if (v == null || v.trim().isEmpty) return null;
    return int.tryParse(v.trim());
  } catch (_) {
    return null;
  }
}

void writeCachedTotalScore(int total) {
  if (total < 0) return;
  final raw = '$total';

  try {
    _auntyStore?.setTotal(raw);
  } catch (_) {}

  try {
    web.window.localStorage.setItem(_totalKey, raw);
  } catch (_) {}
}

/// Boolean flags in localStorage (celebration seen, etc.).
bool? readLocalFlag(String key) {
  final k = key.trim();
  if (k.isEmpty) return null;
  try {
    final v = web.window.localStorage.getItem(k);
    if (v == null) return null;
    final t = v.trim().toLowerCase();
    if (t == '1' || t == 'true') return true;
    if (t == '0' || t == 'false') return false;
    return null;
  } catch (_) {
    return null;
  }
}

void writeLocalFlag(String key, bool value) {
  final k = key.trim();
  if (k.isEmpty) return;
  try {
    web.window.localStorage.setItem(k, value ? '1' : '0');
  } catch (_) {}
}

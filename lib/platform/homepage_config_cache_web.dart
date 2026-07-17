import 'dart:convert';

import 'package:web/web.dart' as web;

import '../models/homepage_config.dart';

const _cacheKey = 'aunty_homepage_config_v1';

/// Instant Highlights from the HTML shell / previous visit (before Firestore).
HomepageConfig? readCachedHomepageConfig() {
  try {
    final raw = web.window.localStorage.getItem(_cacheKey);
    if (raw == null || raw.trim().isEmpty) return null;
    final map = jsonDecode(raw);
    if (map is! Map) return null;
    return HomepageConfig.fromMap(Map<String, dynamic>.from(map));
  } catch (_) {
    return null;
  }
}

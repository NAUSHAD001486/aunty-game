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

void writeCachedHomepageConfig(HomepageConfig config) {
  try {
    final map = <String, dynamic>{
      'offer_image_url': config.offerImage,
      'offer_title': config.offerTitle,
      'offer_desc': config.offerDesc,
      'offer_price': config.offerPrice,
    };
    web.window.localStorage.setItem(_cacheKey, jsonEncode(map));
  } catch (_) {}
}

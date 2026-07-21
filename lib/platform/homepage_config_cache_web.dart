import 'dart:convert';

import 'package:web/web.dart' as web;

import '../models/confirmed_winner.dart';
import '../models/homepage_config.dart';

const _cacheKey = 'aunty_homepage_config_v1';

Map<String, dynamic>? _readRawMap() {
  try {
    final raw = web.window.localStorage.getItem(_cacheKey);
    if (raw == null || raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return Map<String, dynamic>.from(decoded);
  } catch (_) {
    return null;
  }
}

void _writeRawMap(Map<String, dynamic> map) {
  try {
    web.window.localStorage.setItem(_cacheKey, jsonEncode(map));
  } catch (_) {}
}

/// Instant Offer card from previous visit (before Firestore).
HomepageConfig? readCachedHomepageConfig() {
  final map = _readRawMap();
  if (map == null) return null;
  final config = HomepageConfig.fromMap(map);
  return config.hasOffer ? config : null;
}

/// Instant Latest Winner card from previous visit (before Firestore).
ConfirmedWinner? readCachedConfirmedWinner() {
  final map = _readRawMap();
  if (map == null) return null;
  final winner = ConfirmedWinner.fromMap(map);
  return winner.hasWinner ? winner : null;
}

/// Merge offer fields into the shared snapshot (preserves winner keys).
void writeCachedHomepageConfig(HomepageConfig config) {
  final map = _readRawMap() ?? <String, dynamic>{};
  map['offer_image_url'] = config.offerImage;
  map['offer_title'] = config.offerTitle;
  map['offer_desc'] = config.offerDesc;
  map['offer_price'] = config.offerPrice;
  _writeRawMap(map);
}

/// Merge winner fields into the shared snapshot (preserves offer keys).
void writeCachedConfirmedWinner(ConfirmedWinner winner) {
  final map = _readRawMap() ?? <String, dynamic>{};
  map['uid'] = winner.authUid;
  map['playerId'] = winner.playerId;
  map['winner_name'] = winner.name;
  map['winner_photo'] = winner.photo;
  map['winner_score'] = winner.score;
  map['cycleId'] = winner.cycleId;
  _writeRawMap(map);
}

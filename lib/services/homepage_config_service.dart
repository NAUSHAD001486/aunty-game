import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/confirmed_winner.dart';
import '../models/homepage_config.dart';
import '../platform/homepage_config_cache.dart';
import 'score_service.dart';

/// Read-only streams for landing Offer + Latest Winner cards.
/// Completely independent of Flame game boot — only needs Firebase.initializeApp.
class HomepageConfigService {
  HomepageConfigService._();

  static const String collection = 'game_metadata';
  static const String offerDocId = 'homepage_config';
  static const String winnerDocId = 'confirmed_winner';

  static CollectionReference<Map<String, dynamic>> get _meta =>
      FirebaseFirestore.instance.collection(collection);

  static DocumentReference<Map<String, dynamic>> get _offerDoc =>
      _meta.doc(offerDocId);

  static DocumentReference<Map<String, dynamic>> get _winnerDoc =>
      _meta.doc(winnerDocId);

  /// Firebase core only (no Auth). Safe for public `game_metadata` reads.
  static Future<bool> waitForFirebase({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (Firebase.apps.isNotEmpty) return true;
    try {
      final ok = await ScoreService.instance
          .ensureFirebaseCore()
          .timeout(timeout);
      return ok;
    } catch (_) {
      return Firebase.apps.isNotEmpty;
    }
  }

  /// Kick Firebase + streams as early as possible (call from [main]).
  static void warmStart() {
    unawaited(waitForFirebase());
  }

  /// Live offer config (`homepage_config`).
  static Stream<HomepageConfig?> offerStream() {
    return Stream.fromFuture(waitForFirebase()).asyncExpand((ready) {
      if (!ready) return Stream<HomepageConfig?>.value(null);
      return offerStreamAfterReady();
    });
  }

  /// Live confirmed winner (`confirmed_winner`).
  static Stream<ConfirmedWinner?> confirmedWinnerStream() {
    return Stream.fromFuture(waitForFirebase()).asyncExpand((ready) {
      if (!ready) return Stream<ConfirmedWinner?>.value(null);
      return winnerStreamAfterReady();
    });
  }

  /// Combined stream for the promo panel (offer + winner).
  /// Emits the localStorage snapshot immediately, then merges live Firestore
  /// snaps as each doc arrives — does NOT wait for both before painting.
  static Stream<({HomepageConfig? offer, ConfirmedWinner? winner})> stream() {
    return Stream.multi((controller) async {
      final cachedOffer = readCachedHomepageConfig();
      final cachedWinner = readCachedConfirmedWinner();
      controller.add((offer: cachedOffer, winner: cachedWinner));

      final ready = await waitForFirebase();
      if (!controller.isClosed && !ready) {
        controller.add((offer: cachedOffer, winner: cachedWinner));
        await controller.close();
        return;
      }

      HomepageConfig? latestOffer = cachedOffer;
      ConfirmedWinner? latestWinner = cachedWinner;

      void emit() {
        if (controller.isClosed) return;
        controller.add((offer: latestOffer, winner: latestWinner));
      }

      late final StreamSubscription<HomepageConfig?> subOffer;
      late final StreamSubscription<ConfirmedWinner?> subWinner;

      subOffer = offerStreamAfterReady().listen(
        (o) {
          latestOffer = o;
          if (o != null && o.hasOffer) {
            writeCachedHomepageConfig(o);
          }
          emit();
        },
        onError: (Object e, StackTrace st) {
          if (!controller.isClosed) controller.addError(e, st);
        },
      );

      subWinner = winnerStreamAfterReady().listen(
        (w) {
          latestWinner = w;
          if (w != null && w.hasWinner) {
            writeCachedConfirmedWinner(w);
          }
          emit();
        },
        onError: (Object e, StackTrace st) {
          if (!controller.isClosed) controller.addError(e, st);
        },
      );

      controller.onCancel = () async {
        await subOffer.cancel();
        await subWinner.cancel();
      };
    });
  }

  static Stream<HomepageConfig?> offerStreamAfterReady() {
    try {
      return _offerDoc.snapshots().map((snap) {
        if (!snap.exists || snap.data() == null) {
          return const HomepageConfig();
        }
        return HomepageConfig.fromMap(snap.data()!);
      });
    } catch (_) {
      return Stream<HomepageConfig?>.value(const HomepageConfig());
    }
  }

  static Stream<ConfirmedWinner?> winnerStreamAfterReady() {
    try {
      return _winnerDoc.snapshots().map((snap) {
        if (!snap.exists || snap.data() == null) {
          return const ConfirmedWinner();
        }
        return ConfirmedWinner.fromMap(snap.data()!);
      });
    } catch (_) {
      return Stream<ConfirmedWinner?>.value(const ConfirmedWinner());
    }
  }
}

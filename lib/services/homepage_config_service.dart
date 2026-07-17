import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/confirmed_winner.dart';
import '../models/homepage_config.dart';

/// Read-only streams for landing Offer + Latest Winner cards.
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

  /// Wait until [Firebase.initializeApp] finishes (ScoreService.init is deferred
  /// on web). Without this, the promo panel would subscribe once while apps is
  /// empty and never receive Firestore updates.
  static Future<bool> waitForFirebase({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (Firebase.apps.isNotEmpty) return true;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (Firebase.apps.isNotEmpty) return true;
    }
    return Firebase.apps.isNotEmpty;
  }

  /// Live offer config (`homepage_config`).
  static Stream<HomepageConfig?> offerStream() {
    return Stream.fromFuture(waitForFirebase()).asyncExpand((ready) {
      if (!ready) return Stream<HomepageConfig?>.value(null);
      try {
        return _offerDoc.snapshots().map((snap) {
          if (!snap.exists || snap.data() == null) return null;
          return HomepageConfig.fromMap(snap.data()!);
        });
      } catch (_) {
        return Stream<HomepageConfig?>.value(null);
      }
    });
  }

  /// Live confirmed winner (`confirmed_winner`).
  static Stream<ConfirmedWinner?> confirmedWinnerStream() {
    return Stream.fromFuture(waitForFirebase()).asyncExpand((ready) {
      if (!ready) return Stream<ConfirmedWinner?>.value(null);
      try {
        return _winnerDoc.snapshots().map((snap) {
          if (!snap.exists || snap.data() == null) return null;
          return ConfirmedWinner.fromMap(snap.data()!);
        });
      } catch (_) {
        return Stream<ConfirmedWinner?>.value(null);
      }
    });
  }

  /// Combined stream for the promo panel (offer + winner).
  static Stream<({HomepageConfig? offer, ConfirmedWinner? winner})> stream() {
    return Stream.fromFuture(waitForFirebase()).asyncExpand((ready) {
      if (!ready) {
        return Stream.value((offer: null, winner: null));
      }
      try {
        return _combineLatest2(
          offerStreamAfterReady(),
          winnerStreamAfterReady(),
          (HomepageConfig? o, ConfirmedWinner? w) => (offer: o, winner: w),
        );
      } catch (_) {
        return Stream.value((offer: null, winner: null));
      }
    });
  }

  /// Internal: Firebase already confirmed ready (avoid nested wait).
  static Stream<HomepageConfig?> offerStreamAfterReady() {
    try {
      return _offerDoc.snapshots().map((snap) {
        if (!snap.exists || snap.data() == null) return null;
        return HomepageConfig.fromMap(snap.data()!);
      });
    } catch (_) {
      return Stream<HomepageConfig?>.value(null);
    }
  }

  static Stream<ConfirmedWinner?> winnerStreamAfterReady() {
    try {
      return _winnerDoc.snapshots().map((snap) {
        if (!snap.exists || snap.data() == null) return null;
        return ConfirmedWinner.fromMap(snap.data()!);
      });
    } catch (_) {
      return Stream<ConfirmedWinner?>.value(null);
    }
  }

  static Stream<R> _combineLatest2<A, B, R>(
    Stream<A> a,
    Stream<B> b,
    R Function(A, B) combine,
  ) {
    late A latestA;
    late B latestB;
    var hasA = false;
    var hasB = false;

    return Stream<R>.multi((controller) {
      final subA = a.listen(
        (event) {
          latestA = event;
          hasA = true;
          if (hasA && hasB) controller.add(combine(latestA, latestB));
        },
        onError: controller.addError,
        onDone: controller.close,
      );
      final subB = b.listen(
        (event) {
          latestB = event;
          hasB = true;
          if (hasA && hasB) controller.add(combine(latestA, latestB));
        },
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = () async {
        await subA.cancel();
        await subB.cancel();
      };
    });
  }
}

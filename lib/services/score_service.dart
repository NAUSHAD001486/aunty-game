import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import '../platform/stable_player_id.dart';

/// Production score + identity layer for Aunty.
///
/// Collection: `users_scores`
/// Document ID: **stable player id** (web localStorage) — NOT raw Auth uid alone.
///
/// On every successful read/write we also cache `totalScore` in localStorage so
/// a plain F5 refresh can show the last total immediately, then confirm from
/// Firestore.
///
/// Local Chrome tip:
///   Prefer: `bash scripts/run-web-chrome.sh`
///   Plain `flutter run -d chrome` uses a throwaway profile (wipes storage on
///   every process restart). F5 inside the same tab must keep scores — that is
///   covered by LOCAL auth persistence + localStorage playerId/total cache.
class ScoreService {
  ScoreService._();
  static final ScoreService instance = ScoreService._();

  static const String collectionName = 'users_scores';
  static const String claimsCollection = 'winners_claims';
  static const int cycleDays = 30;
  static const int tournamentHours = 12;

  bool _ready = false;
  bool _persistenceConfigured = false;
  String? _playerId;

  /// Single-flight lock — concurrent ensureSignedIn was racing into two
  /// anonymous sign-ins on refresh and orphaning the score document.
  Future<User>? _signInInFlight;

  bool get isReady => _ready;

  /// Live Firestore total for this player (0+). Null = not loaded yet.
  final ValueNotifier<int?> myTotalNotifier = ValueNotifier<int?>(null);

  /// True only for the confirmed 12h tournament winner who has not claimed yet.
  final ValueNotifier<bool> canClaimPrizeNotifier = ValueNotifier<bool>(false);

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Stable score-document id (localStorage on web).
  String? get playerId => _playerId;

  /// Firebase Auth uid (may rotate if persistence fails; scores use [playerId]).
  String? get uid => _ready ? _auth.currentUser?.uid : null;
  String? get displayName =>
      _ready ? _auth.currentUser?.displayName : null;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection(collectionName);

  DocumentReference<Map<String, dynamic>> _playerRef(String id) =>
      _users.doc(id);

  /// Fast path: initialize Firebase only. Auth + profile warm in background.
  Future<bool> init() async {
    if (_ready) return true;
    if (_optionsArePlaceholders()) {
      debugPrint(
        '[ScoreService] firebase_options.dart still has placeholders — '
        'run: flutterfire configure --project=YOUR_PROJECT_ID',
      );
      return false;
    }

    // Instant HUD after F5 — don't wait for network.
    final storedPlayer = readStablePlayerId();
    if (storedPlayer != null && storedPlayer.isNotEmpty) {
      _playerId = storedPlayer;
    }
    final cached = readCachedTotalScore();
    if (cached != null) {
      myTotalNotifier.value = cached;
    }

    try {
      if (Firebase.apps.isEmpty) {
        final options = kIsWeb
            ? DefaultFirebaseOptions.web
            : DefaultFirebaseOptions.currentPlatform;
        await _initializeFirebaseWithRetry(options);
      }
      await _configureWebAuthPersistence();
      _ready = true;
      unawaited(_warmUserProfile());
      if (kDebugMode) {
        debugPrint(
          '[ScoreService] Firebase ready (cachedTotal=$cached, auth warming…)',
        );
      }
      return true;
    } catch (e, st) {
      _ready = false;
      debugPrint('[ScoreService] init failed (game continues offline): $e');
      debugPrint('$st');
      return false;
    }
  }

  /// Web plugins can race on first paint — retry once on channel-error.
  Future<void> _initializeFirebaseWithRetry(FirebaseOptions options) async {
    try {
      await Firebase.initializeApp(options: options)
          .timeout(const Duration(seconds: 10));
      return;
    } catch (e) {
      debugPrint('[ScoreService] initializeApp first attempt failed: $e');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (Firebase.apps.isNotEmpty) return;
      await Firebase.initializeApp(options: options)
          .timeout(const Duration(seconds: 10));
    }
  }

  /// Persist anonymous Auth across reloads (web IndexedDB / localStorage).
  Future<void> _configureWebAuthPersistence() async {
    if (!kIsWeb || _persistenceConfigured) return;
    try {
      await _auth.setPersistence(Persistence.LOCAL);
      _persistenceConfigured = true;
      if (kDebugMode) {
        debugPrint('[ScoreService] Auth persistence = LOCAL');
      }
    } catch (e) {
      debugPrint('[ScoreService] setPersistence(LOCAL) skipped: $e');
    }
  }

  Future<void> _warmUserProfile() async {
    try {
      await ensureSignedIn();
      final total = await fetchMyTotalScore();
      if (total != null) {
        _publishTotal(total);
      } else {
        // Keep cached HUD value; never force 0 on a soft failure.
        myTotalNotifier.value ??= readCachedTotalScore();
      }
      unawaited(refreshClaimEligibility());
      if (kDebugMode) {
        debugPrint(
          '[ScoreService] ready playerId=$_playerId authUid=$uid '
          'total=${myTotalNotifier.value}',
        );
      }
    } catch (e) {
      debugPrint('[ScoreService] auth warm failed: $e');
      myTotalNotifier.value ??= readCachedTotalScore();
    }
  }

  void _publishTotal(int total, {bool allowDowngradeToZero = false}) {
    final cached = readCachedTotalScore();
    // Never let a transient Firestore miss wipe a known-good local total.
    if (!allowDowngradeToZero &&
        total == 0 &&
        cached != null &&
        cached > 0) {
      myTotalNotifier.value = cached;
      return;
    }
    myTotalNotifier.value = total;
    writeCachedTotalScore(total);
  }

  /// Call from game UI (optimistic totals) so F5 still has the last sum.
  void rememberLocalTotal(int total) {
    if (total < 0) return;
    _publishTotal(total);
  }

  bool _optionsArePlaceholders() {
    final o = DefaultFirebaseOptions.web;
    return o.apiKey.startsWith('YOUR_') ||
        o.projectId.startsWith('YOUR_') ||
        o.appId.startsWith('YOUR_');
  }

  String _newPlayerId() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Prefer localStorage → auth-linked Firestore doc → auth.uid → random.
  Future<String> _resolvePlayerId(User user) async {
    final stored = readStablePlayerId();
    if (stored != null && stored.isNotEmpty) {
      _playerId = stored;
      return stored;
    }

    // Auth restored but localStorage empty: recover doc keyed by this auth uid.
    final recovered = await _findExistingPlayerIdForAuth(user.uid);
    if (recovered != null && recovered.isNotEmpty) {
      writeStablePlayerId(recovered);
      _playerId = recovered;
      return recovered;
    }

    final id = user.uid;
    writeStablePlayerId(id);
    _playerId = id;
    return id;
  }

  /// Find an existing score row for this Auth uid (doc id or authUid field).
  Future<String?> _findExistingPlayerIdForAuth(String authUid) async {
    try {
      final direct = await _playerRef(authUid).get(
        const GetOptions(source: Source.serverAndCache),
      );
      if (direct.exists) return authUid;

      final q = await _users
          .where('authUid', isEqualTo: authUid)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) return q.docs.first.id;

      final qUid = await _users.where('uid', isEqualTo: authUid).limit(1).get();
      if (qUid.docs.isNotEmpty) return qUid.docs.first.id;
    } catch (e) {
      debugPrint('[ScoreService] authUid recovery lookup failed: $e');
    }
    return null;
  }

  /// Wait for Auth to restore from IndexedDB before minting a new anonymous user.
  Future<User?> _waitForRestoredUser() async {
    final existing = _auth.currentUser;
    if (existing != null) return existing;

    final completer = Completer<User?>();
    StreamSubscription<User?>? sub;
    Timer? timer;

    void finish(User? user) {
      if (completer.isCompleted) return;
      completer.complete(user);
    }

    // Web Auth often emits `null` first, then the restored user a moment later.
    // Do NOT treat the first null as "logged out".
    timer = Timer(const Duration(milliseconds: 5000), () {
      finish(_auth.currentUser);
    });

    sub = _auth.authStateChanges().listen((user) {
      if (user != null) finish(user);
    });

    // Extra tick — persistence hydrate can land right after initializeApp.
    scheduleMicrotask(() {
      final u = _auth.currentUser;
      if (u != null) finish(u);
    });

    try {
      return await completer.future;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  /// Anonymous Auth + stable player profile doc (single-flight).
  Future<User> ensureSignedIn() async {
    final inFlight = _signInInFlight;
    if (inFlight != null) return inFlight;

    final future = _ensureSignedInBody();
    _signInInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_signInInFlight, future)) {
        _signInInFlight = null;
      }
    }
  }

  Future<User> _ensureSignedInBody() async {
    await _configureWebAuthPersistence();

    var user = await _waitForRestoredUser();
    if (user == null) {
      final cred = await _auth.signInAnonymously();
      user = cred.user;
      if (user == null) {
        throw StateError('Anonymous sign-in returned no user');
      }
      if (kDebugMode) {
        debugPrint('[ScoreService] new anonymous authUid=${user.uid}');
      }
    } else if (kDebugMode) {
      debugPrint('[ScoreService] restored authUid=${user.uid}');
    }

    await _resolvePlayerId(user);
    if (_playerId == null || _playerId!.isEmpty) {
      final id = _newPlayerId();
      writeStablePlayerId(id);
      _playerId = id;
    }

    await _ensureProfileDoc(user, _playerId!);
    return user;
  }

  String defaultDisplayNameFor(String id) {
    final short = id.length >= 5 ? id.substring(0, 5) : id;
    return 'Player_$short';
  }

  /// Save / update custom display name. Empty → `Player_<id5>`.
  Future<String> updateDisplayName(String? name) async {
    if (!_ready) await init();
    final user = await ensureSignedIn();
    final id = _playerId ?? user.uid;
    final trimmed = name?.trim() ?? '';
    final display =
        trimmed.isEmpty ? defaultDisplayNameFor(id) : trimmed;

    await user.updateDisplayName(display);
    await _playerRef(id).set(
      {
        'playerId': id,
        'authUid': user.uid,
        'uid': id,
        'displayName': display,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    return display;
  }

  /// Current cumulative total (30-day cycle aware, read-only).
  Future<int?> fetchMyTotalScore() async {
    if (!_ready) {
      final ok = await init();
      if (!ok) return readCachedTotalScore();
    }
    try {
      final user = await ensureSignedIn();
      final id = _playerId ?? user.uid;
      final snap = await _playerRef(id).get(
        const GetOptions(source: Source.serverAndCache),
      );
      if (!snap.exists) {
        final cached = readCachedTotalScore();
        if (cached != null && cached > 0) {
          // Doc missing but local cache knows the total — repair Firestore.
          myTotalNotifier.value = cached;
          unawaited(_repairMissingDoc(user, id, cached));
          return cached;
        }
        _publishTotal(0, allowDowngradeToZero: true);
        return 0;
      }
      final total = _effectiveTotalFromData(snap.data()!);
      // Doc exists → server is source of truth (incl. 30-day cycle reset to 0).
      _publishTotal(total, allowDowngradeToZero: true);
      return total;
    } catch (e) {
      debugPrint('[ScoreService] fetchMyTotalScore failed: $e');
      return readCachedTotalScore() ?? myTotalNotifier.value;
    }
  }

  /// Recreate a score row from local cache when the Firestore doc was orphaned
  /// by an Auth/playerId race (keeps leaderboard + future accumulates correct).
  Future<void> _repairMissingDoc(User user, String playerId, int total) async {
    try {
      final display = user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : defaultDisplayNameFor(playerId);
      final now = DateTime.now().toUtc();
      await _playerRef(playerId).set(
        {
          'playerId': playerId,
          'authUid': user.uid,
          'uid': playerId,
          'displayName': display,
          'totalScore': total,
          'cycleStartDate': Timestamp.fromDate(now),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastRunScore': 0,
        },
        SetOptions(merge: true),
      );
      writeStablePlayerId(playerId);
      if (kDebugMode) {
        debugPrint(
          '[ScoreService] repaired missing doc playerId=$playerId total=$total',
        );
      }
    } catch (e) {
      debugPrint('[ScoreService] repairMissingDoc failed: $e');
    }
  }

  int _effectiveTotalFromData(Map<String, dynamic> data) {
    final rawCycle = data['cycleStartDate'];
    final now = DateTime.now().toUtc();
    DateTime? cycleStart;
    if (rawCycle is Timestamp) {
      cycleStart = rawCycle.toDate().toUtc();
    } else if (rawCycle is DateTime) {
      cycleStart = rawCycle.toUtc();
    }
    if (cycleStart != null &&
        now.difference(cycleStart).inDays >= cycleDays) {
      return 0;
    }
    return (data['totalScore'] as num?)?.toInt() ?? 0;
  }

  /// READ current `totalScore` → add [runScore] → WRITE sum (never overwrite
  /// with only the run score when a document already exists).
  Future<int?> submitRunScore(int runScore) async {
    if (runScore < 0) return null;

    // Zero-point death: still surface the saved total; don't mint a blank row
    // that can race ahead of auth restore on a fresh page load.
    if (runScore == 0) {
      final existing = await fetchMyTotalScore();
      if (existing != null) {
        _publishTotal(existing);
        return existing;
      }
      return myTotalNotifier.value ?? readCachedTotalScore() ?? 0;
    }

    if (!_ready) {
      final ok = await init();
      if (!ok) return null;
    }

    final user = await ensureSignedIn();
    final id = _playerId ?? user.uid;
    final ref = _playerRef(id);
    final authUid = user.uid;

    try {
      final nextTotal = await _db.runTransaction<int>((tx) async {
        final snap = await tx.get(ref);
        final now = DateTime.now().toUtc();

        String display = user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : defaultDisplayNameFor(id);

        if (!snap.exists) {
          // Brand-new player doc only — starting total is this run.
          final tFields = _tournamentFields(null, runScore, now);
          tx.set(ref, {
            'playerId': id,
            'authUid': authUid,
            'uid': id,
            'displayName': display,
            'totalScore': runScore,
            'cycleStartDate': Timestamp.fromDate(now),
            'updatedAt': FieldValue.serverTimestamp(),
            'lastRunScore': runScore,
            ...tFields,
          });
          return runScore;
        }

        final data = snap.data()!;
        display = (data['displayName'] as String?)?.trim().isNotEmpty == true
            ? (data['displayName'] as String).trim()
            : display;

        final rawCycle = data['cycleStartDate'];
        DateTime cycleStart;
        if (rawCycle is Timestamp) {
          cycleStart = rawCycle.toDate().toUtc();
        } else if (rawCycle is DateTime) {
          cycleStart = rawCycle.toUtc();
        } else {
          cycleStart = now;
        }

        var total = (data['totalScore'] as num?)?.toInt() ?? 0;
        if (now.difference(cycleStart).inDays >= cycleDays) {
          total = 0;
          cycleStart = now;
        }

        final accumulated = total + runScore;
        final tFields = _tournamentFields(data, runScore, now);
        tx.set(
          ref,
          {
            'playerId': id,
            'authUid': authUid,
            'uid': id,
            'displayName': display,
            'totalScore': accumulated,
            'cycleStartDate': Timestamp.fromDate(cycleStart),
            'updatedAt': FieldValue.serverTimestamp(),
            'lastRunScore': runScore,
            ...tFields,
          },
          SetOptions(merge: true),
        );
        return accumulated;
      });

      if (kDebugMode) {
        debugPrint(
          '[ScoreService] playerId=$id run=+$runScore → totalScore=$nextTotal',
        );
      }
      _publishTotal(nextTotal);
      unawaited(refreshClaimEligibility());
      return nextTotal;
    } catch (e, st) {
      debugPrint('[ScoreService] submitRunScore failed: $e');
      debugPrint('$st');
      // Keep optimistic/local cache visible if the write failed.
      return myTotalNotifier.value ?? readCachedTotalScore();
    }
  }

  Stream<List<LeaderboardEntry>> leaderboardStream({int limit = 50}) {
    return _users
        .orderBy('totalScore', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
      return [
        for (var i = 0; i < snap.docs.length; i++)
          LeaderboardEntry.fromDoc(snap.docs[i], rank: i + 1),
      ];
    });
  }

  // ─── 12-hour tournament + prize claim ─────────────────────────────────

  /// Stable id for the current 12-hour UTC window window.
  static String currentTournamentCycleId([DateTime? now]) {
    final n = now ?? DateTime.now().toUtc();
    final windowMs = tournamentHours * Duration.millisecondsPerHour;
    final startMs = (n.millisecondsSinceEpoch ~/ windowMs) * windowMs;
    return '$startMs';
  }

  Map<String, dynamic> _tournamentFields(
    Map<String, dynamic>? existing,
    int runScore,
    DateTime now,
  ) {
    final cycleId = currentTournamentCycleId(now);
    final prev = existing?['tournamentCycleId']?.toString() ?? '';
    var score = (existing?['tournamentScore'] as num?)?.toInt() ?? 0;
    if (prev != cycleId) {
      score = runScore;
    } else {
      score += runScore;
    }
    return {
      'tournamentCycleId': cycleId,
      'tournamentScore': score,
      'tournamentUpdatedAt': FieldValue.serverTimestamp(),
    };
  }

  DocumentReference<Map<String, dynamic>> _claimRef(String authUid) =>
      _db.collection(claimsCollection).doc(authUid);

  /// Recompute whether this anonymous user may claim the prize.
  Future<void> refreshClaimEligibility() async {
    try {
      if (!_ready) {
        final ok = await init();
        if (!ok) {
          canClaimPrizeNotifier.value = false;
          return;
        }
      }
      final user = await ensureSignedIn();
      final authUid = user.uid;

      // Already claimed → never show again.
      final claimSnap = await _claimRef(authUid).get();
      if (claimSnap.exists) {
        canClaimPrizeNotifier.value = false;
        return;
      }

      final confirmed = await _db
          .collection('game_metadata')
          .doc('confirmed_winner')
          .get();
      final confirmedUid = (confirmed.data()?['authUid'] as String?)?.trim() ??
          (confirmed.data()?['uid'] as String?)?.trim() ??
          (confirmed.data()?['winner_uid'] as String?)?.trim() ??
          '';

      if (confirmedUid.isNotEmpty && confirmedUid == authUid) {
        canClaimPrizeNotifier.value = true;
        return;
      }

      // Not the confirmed winner — keep CTA hidden for everyone else.
      canClaimPrizeNotifier.value = false;
    } catch (e) {
      debugPrint('[ScoreService] refreshClaimEligibility failed: $e');
      canClaimPrizeNotifier.value = false;
    }
  }

  /// Winner submits prize claim — one doc per auth uid (no spam).
  Future<bool> submitWinnerClaim({
    required String fullName,
    required String upiId,
    required String profileNote,
  }) async {
    final name = fullName.trim();
    final upi = upiId.trim();
    final note = profileNote.trim();
    if (name.isEmpty || upi.isEmpty) return false;

    if (!_ready) {
      final ok = await init();
      if (!ok) return false;
    }

    try {
      final user = await ensureSignedIn();
      final authUid = user.uid;
      final ref = _claimRef(authUid);

      final existing = await ref.get();
      if (existing.exists) {
        canClaimPrizeNotifier.value = false;
        return false;
      }

      // Soft gate: must still look like the winner before write.
      await refreshClaimEligibility();
      if (!canClaimPrizeNotifier.value) return false;

      final cycleId = currentTournamentCycleId();
      await ref.set({
        'uid': authUid,
        'authUid': authUid,
        'playerId': _playerId ?? authUid,
        'fullName': name,
        'upiId': upi,
        'profileNote': note,
        'cycleId': cycleId,
        'isProcessed': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      canClaimPrizeNotifier.value = false;
      if (kDebugMode) {
        debugPrint('[ScoreService] winner claim saved uid=$authUid');
      }
      return true;
    } catch (e, st) {
      debugPrint('[ScoreService] submitWinnerClaim failed: $e');
      debugPrint('$st');
      return false;
    }
  }

  Future<void> _ensureProfileDoc(User user, String playerId) async {
    final ref = _playerRef(playerId);
    final snap = await ref.get();
    final display = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : defaultDisplayNameFor(playerId);

    if (snap.exists) {
      // Keep authUid fresh when anonymous Auth rotates but playerId stays.
      // Never touch totalScore here.
      await ref.set(
        {
          'playerId': playerId,
          'authUid': user.uid,
          'uid': playerId,
          'displayName':
              (snap.data()?['displayName'] as String?)?.trim().isNotEmpty ==
                      true
                  ? snap.data()!['displayName']
                  : display,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      final total = _effectiveTotalFromData(snap.data()!);
      _publishTotal(total);
      return;
    }

    // Prefer seeding from local cache so a refresh that lost the doc link
    // (rare) doesn't flash a hard zero before the next scored run.
    final seed = readCachedTotalScore() ?? 0;
    final now = DateTime.now().toUtc();
    await ref.set({
      'playerId': playerId,
      'authUid': user.uid,
      'uid': playerId,
      'displayName': display,
      'totalScore': seed,
      'cycleStartDate': Timestamp.fromDate(now),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastRunScore': 0,
    });
    _publishTotal(seed);

    if (user.displayName == null || user.displayName!.trim().isEmpty) {
      await user.updateDisplayName(display);
    }
  }
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.uid,
    required this.displayName,
    required this.totalScore,
    required this.rank,
    this.cycleStartDate,
  });

  final String uid;
  final String displayName;
  final int totalScore;
  final int rank;
  final DateTime? cycleStartDate;

  factory LeaderboardEntry.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required int rank,
  }) {
    final data = doc.data();
    final cycle = data['cycleStartDate'];
    return LeaderboardEntry(
      uid: (data['playerId'] as String?) ??
          (data['uid'] as String?) ??
          doc.id,
      displayName: (data['displayName'] as String?)?.trim().isNotEmpty == true
          ? (data['displayName'] as String).trim()
          : 'Player',
      totalScore: (data['totalScore'] as num?)?.toInt() ?? 0,
      rank: rank,
      cycleStartDate: cycle is Timestamp ? cycle.toDate() : null,
    );
  }
}

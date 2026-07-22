import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  /// Full `users_scores` snapshots after each daily roll (kept ~2 days).
  static const String scoreArchivesCollection = 'score_archives';
  /// Claim form / button stays available this long after winner announce.
  static const int claimWindowHours = 12;
  static const int archiveRetentionDays = 2;
  /// India Standard Time offset used for daily 8 PM score reset.
  static const Duration _istOffset = Duration(hours: 5, minutes: 30);

  bool _ready = false;
  bool _persistenceConfigured = false;
  bool _firebaseCoreReady = false;
  Future<bool>? _firebaseCoreInFlight;
  String? _playerId;

  /// Single-flight lock — concurrent ensureSignedIn was racing into two
  /// anonymous sign-ins on refresh and orphaning the score document.
  Future<User>? _signInInFlight;

  bool get isReady => _ready;

  /// Live Firestore total for this player (0+). Null = not loaded yet.
  final ValueNotifier<int?> myTotalNotifier = ValueNotifier<int?>(null);

  /// True only for the confirmed 12h tournament winner who has not claimed yet.
  final ValueNotifier<bool> canClaimPrizeNotifier = ValueNotifier<bool>(false);

  /// False until the first claim-eligibility evaluation finishes (Firebase + prefs).
  /// UI must not treat `canClaimPrizeNotifier == false` as final while this is false.
  final ValueNotifier<bool> claimEligibilityReadyNotifier =
      ValueNotifier<bool>(false);

  SharedPreferences? _prefs;
  Future<SharedPreferences>? _prefsInFlight;

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

  /// Firebase.initializeApp only — no Auth / score warm.
  /// Used so landing Offer/Winner can stream before Flame or sign-in.
  Future<bool> ensureFirebaseCore() async {
    if (_firebaseCoreReady || Firebase.apps.isNotEmpty) {
      _firebaseCoreReady = true;
      return true;
    }
    if (_optionsArePlaceholders()) return false;

    _firebaseCoreInFlight ??= () async {
      try {
        final options = kIsWeb
            ? DefaultFirebaseOptions.web
            : DefaultFirebaseOptions.currentPlatform;
        await _initializeFirebaseWithRetry(options);
        _firebaseCoreReady = true;
        // ignore: avoid_print
        print('[ScoreService] Firebase core ready (promo streams can start)');
        return true;
      } catch (e, st) {
        _firebaseCoreInFlight = null;
        debugPrint('[ScoreService] ensureFirebaseCore failed: $e');
        debugPrint('$st');
        return false;
      }
    }();
    return _firebaseCoreInFlight!;
  }

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
      final coreOk = await ensureFirebaseCore();
      if (!coreOk) return false;
      await _configureWebAuthPersistence();
      // Prefs are for claim celebration only — never block score uploads.
      try {
        await _ensurePrefs();
      } catch (e) {
        // ignore: avoid_print
        print('[ScoreService] SharedPreferences warm skipped: $e');
        _prefsInFlight = null;
      }
      _ready = true;
      unawaited(_warmUserProfile());
      // ignore: avoid_print
      print('[ScoreService] Firebase ready — scores + claim can proceed');
      return true;
    } catch (e, st) {
      _ready = false;
      debugPrint('[ScoreService] init failed (game continues offline): $e');
      debugPrint('$st');
      return false;
    }
  }

  /// Web plugins can race on first paint — retry a few times on channel-error.
  Future<void> _initializeFirebaseWithRetry(FirebaseOptions options) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 4; attempt++) {
      try {
        if (Firebase.apps.isNotEmpty) return;
        await Firebase.initializeApp(options: options)
            .timeout(const Duration(seconds: 12));
        return;
      } catch (e) {
        lastError = e;
        debugPrint(
          '[ScoreService] initializeApp attempt $attempt failed: $e',
        );
        await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
      }
    }
    if (Firebase.apps.isNotEmpty) return;
    throw lastError ?? StateError('Firebase.initializeApp failed');
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

  void _publishTotal(int total, {bool allowDowngrade = false}) {
    if (total < 0) return;
    final cached = readCachedTotalScore();
    final current = myTotalNotifier.value;
    var floor = current;
    if (cached != null && (floor == null || cached > floor)) {
      floor = cached;
    }

    // Stale/slow Firestore reads must never flash the HUD downward after an
    // optimistic (base+run) total was already shown — except explicit resets.
    if (!allowDowngrade && floor != null && total < floor) {
      myTotalNotifier.value = floor;
      writeCachedTotalScore(floor);
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

  /// Current cumulative total (12h tournament window aware, read-only).
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
        _publishTotal(0, allowDowngrade: true);
        return 0;
      }
      final data = snap.data()!;
      // Lazy 12h roll: archive previous window, then show 0 until next run.
      if (_needsTournamentRoll(data)) {
        unawaited(_archiveAndResetStaleScore(user: user, playerId: id, data: data));
        _publishTotal(0, allowDowngrade: true);
        return 0;
      }
      final total = _effectiveTotalFromData(data);
      _publishTotal(total);
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
          'tournamentScore': total,
          'tournamentCycleId': currentTournamentCycleId(now),
          'cycleStartDate': Timestamp.fromDate(currentTournamentWindowStart(now)),
          'updatedAt': FieldValue.serverTimestamp(),
          'tournamentUpdatedAt': FieldValue.serverTimestamp(),
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
    if (_needsTournamentRoll(data)) return 0;
    return (data['totalScore'] as num?)?.toInt() ?? 0;
  }

  bool _needsTournamentRoll(Map<String, dynamic> data) {
    final cycleId = currentTournamentCycleId();
    final prev = data['tournamentCycleId']?.toString() ?? '';
    if (prev.isNotEmpty) return prev != cycleId;
    // Legacy docs without tournamentCycleId: roll if before current window start.
    final rawCycle = data['cycleStartDate'];
    DateTime? cycleStart;
    if (rawCycle is Timestamp) {
      cycleStart = rawCycle.toDate().toUtc();
    } else if (rawCycle is DateTime) {
      cycleStart = rawCycle.toUtc();
    }
    if (cycleStart == null) return false;
    return cycleStart.isBefore(currentTournamentWindowStart());
  }

  /// READ current `totalScore` → add [runScore] → WRITE sum (never overwrite
  /// with only the run score when a document already exists).
  Future<int?> submitRunScore(int runScore) async {
    // ignore: avoid_print
    print('[Score] submitRunScore called runScore=$runScore ready=$_ready');
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
      // ignore: avoid_print
      print('[Score] init before submit → ok=$ok');
      if (!ok) {
        // ignore: avoid_print
        print('[Score] ABORT — Firebase init failed, cannot upload score');
        return myTotalNotifier.value ?? readCachedTotalScore();
      }
    }

    try {
      final user = await ensureSignedIn();
      final id = _playerId ?? user.uid;
      final ref = _playerRef(id);
      final authUid = user.uid;
      // ignore: avoid_print
      print('[Score] signed in authUid=$authUid playerId=$id');

      // If the daily 8 PM window rolled, archive old scores BEFORE accumulating.
      final pre = await ref.get(const GetOptions(source: Source.serverAndCache));
      if (pre.exists) {
        final preData = pre.data()!;
        if (_needsTournamentRoll(preData)) {
          await _archivePlayerScoreSnapshot(
            playerId: id,
            data: preData,
          );
        }
      }
      unawaited(_purgeExpiredScoreArchives());

      final nextTotal = await _db.runTransaction<int>((tx) async {
        final snap = await tx.get(ref);
        final now = DateTime.now().toUtc();
        final cycleId = currentTournamentCycleId(now);
        final windowStart = currentTournamentWindowStart(now);

        String display = user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : defaultDisplayNameFor(id);

        if (!snap.exists) {
          final tFields = _tournamentFields(null, runScore, now);
          // Prefer local optimistic floor if auth raced ahead of a prior write.
          final local = readCachedTotalScore();
          final seed = (local != null && local > runScore) ? local : runScore;
          tx.set(ref, {
            'playerId': id,
            'authUid': authUid,
            'uid': id,
            'displayName': display,
            'totalScore': seed,
            'cycleStartDate': Timestamp.fromDate(windowStart),
            'updatedAt': FieldValue.serverTimestamp(),
            'lastRunScore': runScore,
            ...tFields,
          });
          return seed;
        }

        final data = snap.data()!;
        display = (data['displayName'] as String?)?.trim().isNotEmpty == true
            ? (data['displayName'] as String).trim()
            : display;

        var total = (data['totalScore'] as num?)?.toInt() ?? 0;
        final prevCycle = data['tournamentCycleId']?.toString() ?? '';
        final rolled = prevCycle != cycleId;
        if (rolled) {
          // New daily window — both competition scores start fresh.
          total = 0;
        }

        var accumulated = total + runScore;
        if (!rolled) {
          // Local cache may already hold optimistic base+run (or a prior
          // submit the server hasn't reflected yet) — never write a lower sum.
          final local = readCachedTotalScore();
          if (local != null && local > accumulated) {
            accumulated = local;
          }
        }

        final tFields = _tournamentFields(data, runScore, now);
        tx.set(ref, {
          'playerId': id,
          'authUid': authUid,
          'uid': id,
          'displayName': display,
          'totalScore': accumulated,
          'cycleStartDate': Timestamp.fromDate(windowStart),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastRunScore': runScore,
          ...tFields,
        });
        return accumulated;
      });

      // ignore: avoid_print
      print('[Score] UPLOADED playerId=$id run=+$runScore → totalScore=$nextTotal');
      // Cycle resets are the only intentional downward publish (handled when
      // fetch sees a roll). Submit path never flashes the HUD downward.
      _publishTotal(nextTotal);
      unawaited(refreshClaimEligibility());
      return nextTotal;
    } catch (e, st) {
      // ignore: avoid_print
      print('[Score] submitRunScore FAILED: $e');
      debugPrint('$st');
      // Keep optimistic/local cache visible if the write failed.
      return myTotalNotifier.value ?? readCachedTotalScore();
    }
  }

  Stream<List<LeaderboardEntry>> leaderboardStream({int limit = 50}) {
    final cycleId = currentTournamentCycleId();
    return _users
        .where('tournamentCycleId', isEqualTo: cycleId)
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

  // ─── Daily 8 PM IST tournament + prize claim ───────────────────────────

  /// Stable id for the current daily competition window (resets 8 PM IST).
  static String currentTournamentCycleId([DateTime? now]) {
    return '${currentTournamentWindowStart(now).millisecondsSinceEpoch}';
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

  /// UTC instant of the last 8:00 PM Asia/Kolkata boundary.
  /// Scores accumulate from that moment until the next 8 PM IST.
  static DateTime currentTournamentWindowStart([DateTime? now]) {
    final utc = (now ?? DateTime.now()).toUtc();
    final ist = utc.add(_istOffset);
    // 20:00 IST == 14:30 UTC same calendar day in IST.
    var startUtc = DateTime.utc(ist.year, ist.month, ist.day, 14, 30);
    if (utc.isBefore(startUtc)) {
      startUtc = startUtc.subtract(const Duration(days: 1));
    }
    return startUtc;
  }

  CollectionReference<Map<String, dynamic>> get _scoreArchives =>
      _db.collection(scoreArchivesCollection);

  /// Copy one player's pre-reset scores into `score_archives` (2-day retention).
  Future<void> _archivePlayerScoreSnapshot({
    required String playerId,
    required Map<String, dynamic> data,
  }) async {
    final oldCycle = data['tournamentCycleId']?.toString() ?? '';
    if (oldCycle.isEmpty) return;

    final total = (data['totalScore'] as num?)?.toInt() ?? 0;
    final tScore = (data['tournamentScore'] as num?)?.toInt() ?? 0;
    if (total <= 0 && tScore <= 0) return;

    final archiveId = '${oldCycle}_$playerId';
    final ref = _scoreArchives.doc(archiveId);
    try {
      final existing = await ref.get();
      if (existing.exists) return;

      final expireAt = DateTime.now()
          .toUtc()
          .add(const Duration(days: archiveRetentionDays));
      await ref.set({
        'cycleId': oldCycle,
        'playerId': playerId,
        'uid': (data['uid'] as String?)?.trim().isNotEmpty == true
            ? data['uid']
            : playerId,
        'authUid': data['authUid'],
        'displayName': data['displayName'],
        'totalScore': total,
        'tournamentScore': tScore,
        'lastRunScore': (data['lastRunScore'] as num?)?.toInt() ?? 0,
        'tournamentCycleId': oldCycle,
        'cycleStartDate': data['cycleStartDate'],
        'sourceUpdatedAt': data['updatedAt'],
        'archivedAt': FieldValue.serverTimestamp(),
        'expireAt': Timestamp.fromDate(expireAt),
      });
      // ignore: avoid_print
      print('[Score] archived $archiveId total=$total tournament=$tScore');
    } catch (e) {
      debugPrint('[ScoreService] archive failed ($archiveId): $e');
    }
  }

  /// Persist reset to 0 when a stale 12h window is discovered on read.
  Future<void> _archiveAndResetStaleScore({
    required User user,
    required String playerId,
    required Map<String, dynamic> data,
  }) async {
    try {
      await _archivePlayerScoreSnapshot(playerId: playerId, data: data);
      final now = DateTime.now().toUtc();
      final cycleId = currentTournamentCycleId(now);
      final windowStart = currentTournamentWindowStart(now);
      final display = (data['displayName'] as String?)?.trim().isNotEmpty == true
          ? (data['displayName'] as String).trim()
          : defaultDisplayNameFor(playerId);
      await _playerRef(playerId).set(
        {
          'playerId': playerId,
          'authUid': user.uid,
          'uid': playerId,
          'displayName': display,
          'totalScore': 0,
          'tournamentScore': 0,
          'tournamentCycleId': cycleId,
          'lastRunScore': 0,
          'cycleStartDate': Timestamp.fromDate(windowStart),
          'updatedAt': FieldValue.serverTimestamp(),
          'tournamentUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      writeCachedTotalScore(0);
      // ignore: avoid_print
      print('[Score] reset playerId=$playerId for cycle=$cycleId');
      unawaited(_purgeExpiredScoreArchives());
    } catch (e) {
      debugPrint('[ScoreService] archiveAndResetStaleScore failed: $e');
    }
  }

  /// Best-effort delete of archives past expireAt (any signed-in client).
  Future<void> _purgeExpiredScoreArchives() async {
    try {
      final now = Timestamp.now();
      final snap = await _scoreArchives
          .where('expireAt', isLessThanOrEqualTo: now)
          .limit(25)
          .get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      // ignore: avoid_print
      print('[Score] purged ${snap.docs.length} expired score_archives');
    } catch (e) {
      debugPrint('[ScoreService] purgeExpiredScoreArchives skipped: $e');
    }
  }

  DocumentReference<Map<String, dynamic>> _claimRef(String claimId) =>
      _db.collection(claimsCollection).doc(claimId);

  DocumentReference<Map<String, dynamic>> get _confirmedWinnerRef =>
      _db.collection('game_metadata').doc('confirmed_winner');

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _claimDocSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _confirmedWinnerSub;
  String? _watchedClaimUid;
  Timer? _claimExpiryTimer;

  /// PhonePe / GPay number (≥10 digits) or UPI id (`local@handle`).
  static bool isValidUpiOrPhone(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    if (t.contains('@')) {
      final parts = t.split('@');
      return parts.length == 2 &&
          parts[0].trim().isNotEmpty &&
          parts[1].trim().isNotEmpty;
    }
    final digits = t.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 10;
  }

  /// Optional email — empty OK; if provided must look like an email.
  static bool isValidOptionalEmail(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return true;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t);
  }

  /// One celebration per Firebase winner announcement (not a fixed date).
  /// When admin replaces `confirmed_winner.uid`, a new key is used automatically.
  static String celebrationSeenPrefsKey({
    required String confirmedUid,
    required String playerId,
  }) {
    return 'seen_popup_${confirmedUid}_$playerId';
  }

  Future<SharedPreferences> _ensurePrefs() async {
    if (_prefs != null) return _prefs!;
    try {
      _prefsInFlight ??= SharedPreferences.getInstance().then((p) {
        _prefs = p;
        return p;
      });
      return await _prefsInFlight!;
    } catch (e) {
      _prefsInFlight = null;
      rethrow;
    }
  }

  /// Stable users_scores document id (localStorage) — NOT FirebaseAuth uid.
  String? get stableScoreDocId {
    final id = (_playerId ?? readStablePlayerId())?.trim();
    if (id == null || id.isEmpty) return null;
    return id;
  }

  /// Reads winner id from `game_metadata/confirmed_winner` — field **`uid` only**.
  static String? confirmedUidFromData(Map<String, dynamic>? docData) {
    if (docData == null) return null;
    final confirmedUid = docData['uid'] as String?;
    final t = confirmedUid?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  /// Latest `confirmed_winner.uid` from Firestore (live admin edits).
  Future<String?> readConfirmedWinnerUid() async {
    try {
      final snap = await _confirmedWinnerRef.get();
      return confirmedUidFromData(snap.data());
    } catch (e) {
      // ignore: avoid_print
      print('[Claim] readConfirmedWinnerUid failed: $e');
      return null;
    }
  }

  /// Confetti once per Firebase winner announcement (localStorage + prefs).
  Future<bool> hasSeenCelebrationPopup(String playerId) async {
    final confirmedUid = await readConfirmedWinnerUid();
    if (confirmedUid == null || confirmedUid.isEmpty) {
      // No announced winner — do not show celebration.
      return true;
    }
    final key = celebrationSeenPrefsKey(
      confirmedUid: confirmedUid,
      playerId: playerId,
    );
    final localKey = 'aunty_$key';

    // Web localStorage is the reliable path across game opens.
    final local = readLocalFlag(localKey);
    if (local == true) {
      // ignore: avoid_print
      print('[Claim] localStorage $localKey = true');
      return true;
    }

    try {
      final prefs = await _ensurePrefs();
      final seen = prefs.getBool(key) == true;
      // ignore: avoid_print
      print('[Claim] prefs $key = $seen');
      if (seen) {
        writeLocalFlag(localKey, true);
        return true;
      }
      return false;
    } catch (e) {
      // ignore: avoid_print
      print('[Claim] prefs read failed (local=$local): $e');
      return local == true;
    }
  }

  Future<void> markCelebrationPopupSeen(String playerId) async {
    final confirmedUid = await readConfirmedWinnerUid();
    if (confirmedUid == null || confirmedUid.isEmpty) return;
    final key = celebrationSeenPrefsKey(
      confirmedUid: confirmedUid,
      playerId: playerId,
    );
    final localKey = 'aunty_$key';
    writeLocalFlag(localKey, true);
    try {
      final prefs = await _ensurePrefs();
      await prefs.setBool(key, true);
      // ignore: avoid_print
      print('[Claim] marked celebration seen key=$key (+ localStorage)');
    } catch (e) {
      // ignore: avoid_print
      print('[Claim] prefs write failed (localStorage saved): $e');
    }
  }

  /// Live watches: local score doc id + live `confirmed_winner` (admin can
  /// replace `uid` anytime — eligibility updates from the snapshot).
  void _ensureClaimWatches(String playerId) {
    if (_watchedClaimUid != playerId) {
      _claimDocSub?.cancel();
      _claimDocSub = null;
      _confirmedWinnerSub?.cancel();
      _confirmedWinnerSub = null;
      _watchedClaimUid = playerId;
    }

    _claimDocSub ??= _claimRef(playerId).snapshots().listen(
      (snap) {
        // ignore: avoid_print
        print(
          '[Claim] winners_claims/$playerId snapshot exists=${snap.exists}',
        );
        unawaited(_recomputeClaimEligibility(playerId: playerId));
      },
      onError: (Object e) {
        // ignore: avoid_print
        print(
          '[Claim] claim doc watch error (still recomputing via get): $e',
        );
        unawaited(_recomputeClaimEligibility(playerId: playerId));
      },
    );

    _confirmedWinnerSub ??= _confirmedWinnerRef.snapshots().listen(
      (snap) {
        final confirmedUid = confirmedUidFromData(snap.data());
        // ignore: avoid_print
        print(
          '[Claim] confirmed_winner live update uid=$confirmedUid '
          '(admin can replace this field anytime)',
        );
        unawaited(_recomputeClaimEligibility(playerId: playerId));
      },
      onError: (Object e) {
        // ignore: avoid_print
        print('[Claim] confirmed_winner watch error: $e');
      },
    );
  }

  /// Returns whether a claim doc exists. `null` = unknown (should not hide UI).
  ///
  /// Old Firestore rules denied get on missing docs (`resource == null`), which
  /// threw permission-denied and permanently hid the claim button. Treat that
  /// as "no claim yet" so the winner UI still works until rules are redeployed.
  Future<bool?> _claimDocExists(String claimId) async {
    try {
      final snap = await _claimRef(claimId).get();
      return snap.exists;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        // ignore: avoid_print
        print(
          '[Claim] winners_claims/$claimId get permission-denied '
          '(treat as no claim — deploy updated firestore.rules)',
        );
        return false;
      }
      // ignore: avoid_print
      print('[Claim] winners_claims/$claimId get failed: $e');
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[Claim] winners_claims/$claimId get failed: $e');
      return null;
    }
  }

  DateTime? _asUtcDateTime(Object? raw) {
    if (raw is Timestamp) return raw.toDate().toUtc();
    if (raw is DateTime) return raw.toUtc();
    return null;
  }

  /// Prefer Firestore `claimExpiresAt` / `announcedAt+12h`, else first-seen+12h.
  Future<DateTime> _resolveClaimDeadline({
    required String confirmedUid,
    required Map<String, dynamic>? confirmedData,
  }) async {
    final data = confirmedData;
    if (data != null) {
      final expires = _asUtcDateTime(
        data['claimExpiresAt'] ?? data['claim_expires_at'],
      );
      if (expires != null) return expires;

      final announced = _asUtcDateTime(
        data['announcedAt'] ??
            data['announced_at'] ??
            data['createdAt'] ??
            data['created_at'],
      );
      if (announced != null) {
        return announced.add(const Duration(hours: claimWindowHours));
      }
    }

    final key = 'claim_deadline_$confirmedUid';
    try {
      final prefs = await _ensurePrefs();
      final ms = prefs.getInt(key);
      if (ms != null && ms > 0) {
        return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
      }
      final deadline =
          DateTime.now().toUtc().add(const Duration(hours: claimWindowHours));
      await prefs.setInt(key, deadline.millisecondsSinceEpoch);
      // ignore: avoid_print
      print('[Claim] local claim deadline set → $deadline');
      return deadline;
    } catch (e) {
      // ignore: avoid_print
      print('[Claim] claim deadline prefs failed: $e');
      return DateTime.now().toUtc().add(const Duration(hours: claimWindowHours));
    }
  }

  void _scheduleClaimExpiry(DateTime deadline) {
    _claimExpiryTimer?.cancel();
    final delay = deadline.difference(DateTime.now().toUtc());
    if (delay.isNegative) {
      canClaimPrizeNotifier.value = false;
      return;
    }
    _claimExpiryTimer = Timer(delay + const Duration(seconds: 1), () {
      // ignore: avoid_print
      print('[Claim] claim window expired — hiding button');
      canClaimPrizeNotifier.value = false;
      unawaited(refreshClaimEligibility());
    });
  }

  /// Match: stable users_scores id == confirmed_winner.`uid`
  /// AND winners_claims/{id} does not exist.
  Future<void> _recomputeClaimEligibility({required String playerId}) async {
    try {
      final me = playerId.trim();

      // Public metadata first — never blocked by winners_claims rules.
      final confirmed = await _confirmedWinnerRef.get();
      final winnerId = confirmedUidFromData(confirmed.data()) ?? '';

      if (winnerId.isEmpty) {
        // ignore: avoid_print
        print('[Claim] HIDE button — confirmed_winner.uid empty');
        canClaimPrizeNotifier.value = false;
        claimEligibilityReadyNotifier.value = true;
        return;
      }

      if (winnerId != me) {
        // ignore: avoid_print
        print(
          '[Claim] HIDE button — uid mismatch '
          '(meScoreDocId=$me confirmed_winner.uid=$winnerId)',
        );
        canClaimPrizeNotifier.value = false;
        claimEligibilityReadyNotifier.value = true;
        return;
      }

      final claimExists = await _claimDocExists(me);
      if (claimExists == true) {
        // ignore: avoid_print
        print('[Claim] HIDE button — winners_claims/$me already exists');
        canClaimPrizeNotifier.value = false;
        claimEligibilityReadyNotifier.value = true;
        return;
      }
      if (claimExists == null) {
        // ignore: avoid_print
        print(
          '[Claim] HIDE button — could not read winners_claims/$me '
          '(unknown state)',
        );
        canClaimPrizeNotifier.value = false;
        claimEligibilityReadyNotifier.value = true;
        return;
      }

      final deadline = await _resolveClaimDeadline(
        confirmedUid: winnerId,
        confirmedData: confirmed.data(),
      );
      final now = DateTime.now().toUtc();
      if (!now.isBefore(deadline)) {
        // ignore: avoid_print
        print('[Claim] HIDE button — claim window ended at $deadline');
        _claimExpiryTimer?.cancel();
        canClaimPrizeNotifier.value = false;
        claimEligibilityReadyNotifier.value = true;
        return;
      }

      // ignore: avoid_print
      print(
        '[Claim] SHOW button — confirmed_winner.uid match & no claim '
        '(meScoreDocId=$me deadline=$deadline)',
      );
      _scheduleClaimExpiry(deadline);
      canClaimPrizeNotifier.value = true;
      claimEligibilityReadyNotifier.value = true;
    } catch (e) {
      // ignore: avoid_print
      print(
        '[Claim] eligibility error (keeping previous '
        'canClaim=${canClaimPrizeNotifier.value}): $e',
      );
      claimEligibilityReadyNotifier.value = true;
    }
  }

  /// Recompute whether this player may claim the prize.
  Future<void> refreshClaimEligibility() async {
    try {
      if (!_ready) {
        final ok = await init();
        if (!ok) {
          // ignore: avoid_print
          print('[Claim] HIDE — ScoreService.init failed / not ready');
          canClaimPrizeNotifier.value = false;
          claimEligibilityReadyNotifier.value = true;
          return;
        }
      }
      try {
        await _ensurePrefs();
      } catch (_) {}

      await ensureSignedIn();
      final me = stableScoreDocId;
      if (me == null) {
        // ignore: avoid_print
        print('[Claim] HIDE — stableScoreDocId missing');
        canClaimPrizeNotifier.value = false;
        claimEligibilityReadyNotifier.value = true;
        return;
      }

      // ignore: avoid_print
      print('[Claim] refreshClaimEligibility scoreDocId=$me');
      _ensureClaimWatches(me);
      await _recomputeClaimEligibility(playerId: me);
    } catch (e) {
      // ignore: avoid_print
      print('[Claim] refreshClaimEligibility failed: $e');
      claimEligibilityReadyNotifier.value = true;
    }
  }

  /// Winner submits contact-only claim keyed by stable score document id.
  Future<WinnerClaimSubmitResult> submitWinnerClaim({
    required String fullName,
    required String upiId,
    String email = '',
    String profileNote = '',
  }) async {
    final name = fullName.trim();
    final upi = upiId.trim();
    final mail = email.trim();
    final note = profileNote.trim();

    if (name.isEmpty || !isValidUpiOrPhone(upi) || !isValidOptionalEmail(mail)) {
      return WinnerClaimSubmitResult.failed;
    }

    if (!_ready) {
      final ok = await init();
      if (!ok) return WinnerClaimSubmitResult.failed;
    }

    try {
      final user = await ensureSignedIn();
      final me = stableScoreDocId ?? user.uid;
      final ref = _claimRef(me);
      _ensureClaimWatches(me);

      final confirmed = await _confirmedWinnerRef.get();
      final winnerId = confirmedUidFromData(confirmed.data()) ?? '';
      if (winnerId.isEmpty || winnerId != me) {
        // ignore: avoid_print
        print(
          '[Claim] submit blocked — uid mismatch '
          '(meScoreDocId=$me confirmed_winner.uid=$winnerId)',
        );
        return WinnerClaimSubmitResult.failed;
      }

      final deadline = await _resolveClaimDeadline(
        confirmedUid: winnerId,
        confirmedData: confirmed.data(),
      );
      if (!DateTime.now().toUtc().isBefore(deadline)) {
        // ignore: avoid_print
        print('[Claim] submit blocked — claim window ended at $deadline');
        canClaimPrizeNotifier.value = false;
        return WinnerClaimSubmitResult.failed;
      }

      final claimExists = await _claimDocExists(me);
      if (claimExists == true) {
        // ignore: avoid_print
        print('[Claim] submit blocked — winners_claims/$me already exists');
        canClaimPrizeNotifier.value = false;
        return WinnerClaimSubmitResult.alreadySubmitted;
      }

      // Contact fields only (+ identity keys required by security rules).
      // Never write totalScore / highScore / tournamentScore.
      final payload = <String, dynamic>{
        'fullName': name,
        'upiId': upi,
        if (mail.isNotEmpty) 'email': mail,
        if (note.isNotEmpty) 'profileNote': note,
        // System identity (not editable by the form UI):
        'uid': me,
        'playerId': me,
        'authUid': user.uid,
        'isProcessed': false,
        'createdAt': FieldValue.serverTimestamp(),
      };
      await ref.set(payload);

      canClaimPrizeNotifier.value = false;
      // ignore: avoid_print
      print('[Claim] submit OK claimId=$me (contact-only payload)');
      return WinnerClaimSubmitResult.success;
    } catch (e, st) {
      debugPrint('[ScoreService] submitWinnerClaim failed: $e');
      debugPrint('$st');
      return WinnerClaimSubmitResult.failed;
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
      'tournamentScore': seed,
      'tournamentCycleId': currentTournamentCycleId(now),
      'cycleStartDate': Timestamp.fromDate(currentTournamentWindowStart(now)),
      'updatedAt': FieldValue.serverTimestamp(),
      'tournamentUpdatedAt': FieldValue.serverTimestamp(),
      'lastRunScore': 0,
    });
    _publishTotal(seed);

    if (user.displayName == null || user.displayName!.trim().isEmpty) {
      await user.updateDisplayName(display);
    }
  }
}

/// Result of [ScoreService.submitWinnerClaim].
enum WinnerClaimSubmitStatus { success, alreadySubmitted, failed }

class WinnerClaimSubmitResult {
  const WinnerClaimSubmitResult._(this.status);

  final WinnerClaimSubmitStatus status;

  static const success =
      WinnerClaimSubmitResult._(WinnerClaimSubmitStatus.success);
  static const alreadySubmitted =
      WinnerClaimSubmitResult._(WinnerClaimSubmitStatus.alreadySubmitted);
  static const failed =
      WinnerClaimSubmitResult._(WinnerClaimSubmitStatus.failed);

  static const String alreadySubmittedMessage =
      'आपका डेटा इस टूर्नामेंट के लिए पहले से मौजूद है! (Your data is already submitted for this tournament)';

  bool get isSuccess => status == WinnerClaimSubmitStatus.success;
  bool get isAlreadySubmitted =>
      status == WinnerClaimSubmitStatus.alreadySubmitted;
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

/// Confirmed / displayed tournament winner for the landing card.
///
/// Firestore: `game_metadata/confirmed_winner`
class ConfirmedWinner {
  const ConfirmedWinner({
    this.authUid = '',
    this.playerId = '',
    this.name = '',
    this.photo = '',
    this.score = 0,
    this.cycleId = '',
  });

  final String authUid;
  final String playerId;
  final String name;
  final String photo;
  final int score;
  final String cycleId;

  bool get hasWinner =>
      name.trim().isNotEmpty ||
      photo.trim().isNotEmpty ||
      score > 0 ||
      authUid.trim().isNotEmpty;

  factory ConfirmedWinner.fromMap(Map<String, dynamic> data) {
    return ConfirmedWinner(
      authUid: _firstString(data, const [
        'uid',
        'authUid',
        'auth_uid',
        'winner_uid',
      ]),
      playerId: _firstString(data, const [
        'playerId',
        'player_id',
        'winner_player_id',
      ]),
      name: _firstString(data, const [
        'winner_name',
        'name',
        'displayName',
      ]),
      photo: _firstString(data, const [
        'winner_photo',
        'photo',
        'photo_url',
        'winner_photo_url',
      ]),
      score: _asInt(
        data['winner_score'] ?? data['score'] ?? data['high_score'],
      ),
      cycleId: _firstString(data, const ['cycleId', 'cycle_id', 'windowId']),
    );
  }

  static String _firstString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final v = data[key];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }
}

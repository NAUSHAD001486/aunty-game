import 'package:flutter/material.dart';

import '../services/score_service.dart';

/// Real-time leaderboard for `users_scores` (totalScore desc).
class LeaderboardPanel extends StatelessWidget {
  const LeaderboardPanel({super.key, this.limit = 50});

  final int limit;

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: const Color(0xCC000000),
      builder: (_) => const Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        child: LeaderboardPanel(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid = ScoreService.instance.uid;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 360,
        constraints: const BoxConstraints(maxHeight: 480),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF121826), Color(0xFF1B2740)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF72F2FF), width: 1.4),
          boxShadow: const [
            BoxShadow(
              color: Color(0x6638D5FF),
              blurRadius: 18,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Leaderboard',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _editName(context),
                    child: const Text(
                      'Name',
                      style: TextStyle(
                        color: Color(0xFF72F2FF),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(40, 40),
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text(
                      '✕',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0x33FFFFFF)),
            Expanded(
              child: StreamBuilder<List<LeaderboardEntry>>(
                stream: ScoreService.instance.leaderboardStream(limit: limit),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Leaderboard unavailable.\n${snap.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFFFB4B4),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF31D5FF),
                      ),
                    );
                  }
                  final rows = snap.data!;
                  if (rows.isEmpty) {
                    return const Center(
                      child: Text(
                        'No scores yet — be the first!',
                        style: TextStyle(color: Color(0xFFB6EEFF)),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final e = rows[index];
                      final mine = e.uid == myUid;
                      return _RankRow(entry: e, highlight: mine);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editName(BuildContext context) async {
    final controller = TextEditingController(
      text: ScoreService.instance.displayName ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF171D2E),
        title: const Text(
          'Display name',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Leave empty for Player_xxxxx',
            hintStyle: TextStyle(color: Colors.white54),
            counterStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF72F2FF)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF31D5FF), width: 2),
            ),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text(
              'Save',
              style: TextStyle(
                color: Color(0xFF31D5FF),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    await ScoreService.instance.updateDisplayName(result);
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.entry, required this.highlight});

  final LeaderboardEntry entry;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final medal = switch (entry.rank) {
      1 => '1',
      2 => '2',
      3 => '3',
      _ => '${entry.rank}',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlight
            ? const Color(0x3331D5FF)
            : const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight
              ? const Color(0xFF31D5FF)
              : const Color(0x22FFFFFF),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              medal,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: entry.rank <= 3
                    ? const Color(0xFFF0C35A)
                    : const Color(0xFFB6EEFF),
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          Text(
            '${entry.totalScore}',
            style: const TextStyle(
              color: Color(0xFF72F2FF),
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

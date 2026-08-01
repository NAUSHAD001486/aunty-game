import 'package:flutter/material.dart';

import '../models/confirmed_winner.dart';
import '../models/homepage_config.dart';
import '../platform/homepage_config_cache.dart';
import '../platform/open_url.dart';
import '../services/homepage_config_service.dart';

/// Landing block below the play card — Latest Winner showcase only.
/// Firestore streams stay independent of Flame game boot.
class HomepagePromoPanel extends StatelessWidget {
  const HomepagePromoPanel({super.key});

  static const surface = Color(0xFFF4F6F8);
  static const _ink = Color(0xFF121820);
  static const _gold = Color(0xFFC9A227);
  static const _goldDeep = Color(0xFF8B6914);
  static const _line = Color(0x140A1620);

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final compact = w < 520;
    final side = compact ? 8.0 : 12.0;
    final cachedWinner = readCachedConfirmedWinner();

    return ColoredBox(
      color: surface,
      child: StreamBuilder<({HomepageConfig? offer, ConfirmedWinner? winner})>(
        initialData: (offer: null, winner: cachedWinner),
        stream: HomepageConfigService.stream(),
        builder: (context, snapshot) {
          final winner = snapshot.data?.winner ?? cachedWinner;
          final winnerLoading = winner == null;

          return Padding(
            padding: EdgeInsets.fromLTRB(
              side,
              compact ? 8 : 10,
              side,
              compact ? 10 : 14,
            ),
            child: _WinnerShowcase(
              winner: winner,
              loading: winnerLoading,
              compact: compact,
            ),
          );
        },
      ),
    );
  }
}

/// Site footer — distinct band below winner (home only, no game impact).
class LandingPrivacyFooter extends StatelessWidget {
  const LandingPrivacyFooter({super.key});

  static const _band = Color(0xFFE8ECF0);
  static const _muted = Color(0xFF5A6570);
  /// Same weight/size as before — softer color so links feel less “highlighted”.
  static const _navStyle = TextStyle(
    fontSize: 13,
    letterSpacing: 0.2,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: Color(0xFF6B7580),
  );
  static const _legalStyle = TextStyle(
    fontSize: 12,
    letterSpacing: 0.2,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final compact = w < 520;

    return ColoredBox(
      color: _band,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 16 : 28,
          compact ? 36 : 42,
          compact ? 16 : 28,
          compact ? 44 : 48,
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                width: compact ? 28 : 36,
                height: 0.5,
                color: const Color(0x35C9A227),
              ),
            ),
            SizedBox(height: compact ? 20 : 22),
            Text(
              'AuntyPari',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: HomepagePromoPanel._ink.withValues(alpha: 0.88),
                fontSize: compact ? 13 : 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.45,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Free online · Daily champion',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _muted.withValues(alpha: 0.85),
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
            SizedBox(height: compact ? 22 : 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              runSpacing: 2,
              children: [
                _FooterTextLink(label: 'Blog', onTap: openBlog),
                _FooterDot(),
                _FooterTextLink(label: 'How to Play', onTap: openHowToPlay),
                _FooterDot(),
                _FooterTextLink(label: 'About Us', onTap: openAboutUs),
              ],
            ),
            SizedBox(height: compact ? 12 : 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: openPrivacyPolicy,
                  style: TextButton.styleFrom(
                    foregroundColor: _muted,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Privacy Policy', style: _legalStyle),
                ),
                const _FooterDot(legal: true),
                TextButton(
                  onPressed: openTerms,
                  style: TextButton.styleFrom(
                    foregroundColor: _muted,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Terms of Use', style: _legalStyle),
                ),
              ],
            ),
            SizedBox(height: compact ? 16 : 18),
            Text(
              '© ${DateTime.now().year} AuntyPari',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _muted.withValues(alpha: 0.65),
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterDot extends StatelessWidget {
  const _FooterDot({this.legal = false});

  final bool legal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: legal ? 2 : 4),
      child: Text(
        '·',
        style: TextStyle(
          color: HomepagePromoPanel._gold.withValues(alpha: 0.55),
          fontSize: legal ? 12 : 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FooterTextLink extends StatelessWidget {
  const _FooterTextLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF6B7580),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: LandingPrivacyFooter._navStyle),
    );
  }
}

/// Full-width champion banner — avatar + identity in one composed strip.
class _WinnerShowcase extends StatelessWidget {
  const _WinnerShowcase({
    required this.winner,
    required this.loading,
    required this.compact,
  });

  final ConfirmedWinner? winner;
  final bool loading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final w = winner;
    final hasData = w?.hasWinner == true;
    final showShimmer = loading && !hasData;
    final name = hasData && w!.name.isNotEmpty ? w.name : 'Coming soon';
    final score = hasData ? w!.score : 0;
    final avatarSize = compact ? 112.0 : 128.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: HomepagePromoPanel._line),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFFBF0),
            Color(0xFFFFFFFF),
            Color(0xFFFFF8E7),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: HomepagePromoPanel._gold.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 2,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFE8D078),
                    Color(0xFFC9A227),
                    Color(0xFFE8D078),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 22,
                compact ? 14 : 18,
                // Pull the whole winner composition toward the right edge.
                compact ? 6 : 14,
                compact ? 14 : 18,
              ),
              child: compact
                  ? _CompactWinnerBody(
                      showShimmer: showShimmer,
                      name: name,
                      score: score,
                      photoUrl: w?.photo ?? '',
                      avatarSize: avatarSize,
                    )
                  : _WideWinnerBody(
                      showShimmer: showShimmer,
                      name: name,
                      score: score,
                      photoUrl: w?.photo ?? '',
                      avatarSize: avatarSize,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WideWinnerBody extends StatelessWidget {
  const _WideWinnerBody({
    required this.showShimmer,
    required this.name,
    required this.score,
    required this.photoUrl,
    required this.avatarSize,
  });

  final bool showShimmer;
  final String name;
  final int score;
  final String photoUrl;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showShimmer)
          _ShimmerCircle(size: avatarSize)
        else
          _WinnerAvatar(photoUrl: photoUrl, size: avatarSize),
        const SizedBox(width: 20),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Latest Winner',
                style: TextStyle(
                  color: HomepagePromoPanel._goldDeep,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              if (showShimmer) ...[
                const _ShimmerLine(widthFactor: 0.55, height: 18),
                const SizedBox(height: 10),
                const _ShimmerLine(widthFactor: 0.32, height: 24),
              ] else ...[
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: HomepagePromoPanel._ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.15,
                  ),
                ),
                const SizedBox(height: 8),
                _ScorePill(score: score),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CompactWinnerBody extends StatelessWidget {
  const _CompactWinnerBody({
    required this.showShimmer,
    required this.name,
    required this.score,
    required this.photoUrl,
    required this.avatarSize,
  });

  final bool showShimmer;
  final String name;
  final int score;
  final String photoUrl;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    // Title sits directly above the photo; name + score sit to the right.
    // Whole block is right-aligned for a clean mobile composition.
    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _LatestWinnerTitle(),
              const SizedBox(height: 8),
              if (showShimmer)
                _ShimmerCircle(size: avatarSize)
              else
                _WinnerAvatar(photoUrl: photoUrl, size: avatarSize),
            ],
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: avatarSize * 1.15),
            child: showShimmer
                ? const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ShimmerLine(widthFactor: 0.9, height: 15),
                      SizedBox(height: 10),
                      _ShimmerLine(widthFactor: 0.65, height: 22),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: HomepagePromoPanel._ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.12,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _ScorePill(score: score),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Compact stylish label — sits above the winner photo.
class _LatestWinnerTitle extends StatelessWidget {
  const _LatestWinnerTitle();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Latest Winner',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: HomepagePromoPanel._goldDeep.withValues(alpha: 0.95),
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            fontStyle: FontStyle.italic,
            letterSpacing: 0.9,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 34,
          height: 1.25,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(1),
            gradient: LinearGradient(
              colors: [
                HomepagePromoPanel._gold.withValues(alpha: 0.05),
                HomepagePromoPanel._gold.withValues(alpha: 0.75),
                HomepagePromoPanel._gold.withValues(alpha: 0.05),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    // Soft, compact pill — no Material icons (web often shows broken □ glyphs).
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEE8D8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x28A8892A)),
      ),
      child: Text(
        score > 0 ? 'Score  $score' : 'Score  —',
        style: const TextStyle(
          color: Color(0xFF6E5C28),
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.12,
          height: 1.2,
        ),
      ),
    );
  }
}

class _WinnerAvatar extends StatelessWidget {
  const _WinnerAvatar({required this.photoUrl, this.size = 88});

  final String photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl.trim().isNotEmpty;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: HomepagePromoPanel._gold, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40C9A227),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: ClipOval(
        child: hasPhoto
            ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                width: size,
                height: size,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const _AvatarFallback(),
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return const ColoredBox(color: Color(0xFFFFF8E7));
                },
              )
            : const _AvatarFallback(),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFFFF8E7),
      child: Center(
        child: Text(
          '★',
          style: TextStyle(
            color: Color(0x88C9A227),
            fontSize: 28,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _ShimmerBlock extends StatefulWidget {
  const _ShimmerBlock();

  @override
  State<_ShimmerBlock> createState() => _ShimmerBlockState();
}

class _ShimmerBlockState extends State<_ShimmerBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = 0.45 + (_c.value * 0.35);
        return ColoredBox(color: Color.fromRGBO(220, 224, 230, t));
      },
    );
  }
}

class _ShimmerLine extends StatelessWidget {
  const _ShimmerLine({this.widthFactor = 1, this.height = 12});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: const _ShimmerBlock(),
        ),
      ),
    );
  }
}

class _ShimmerCircle extends StatelessWidget {
  const _ShimmerCircle({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: const _ShimmerBlock(),
      ),
    );
  }
}

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
              compact ? 6 : 10,
              side,
              compact ? 6 : 14,
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

/// Footer links: Blog · How to Play · About Us · Privacy · Terms
class LandingPrivacyFooter extends StatelessWidget {
  const LandingPrivacyFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 520;

    return Container(
      width: double.infinity,
      color: HomepagePromoPanel.surface,
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 12,
        compact ? 4 : 8,
        compact ? 16 : 12,
        compact ? 22 : 28,
      ),
      child: compact ? const _MobileFooterLinks() : const _DesktopFooterLinks(),
    );
  }
}

class _DesktopFooterLinks extends StatelessWidget {
  const _DesktopFooterLinks();

  static const _style = TextStyle(
    fontSize: 13,
    letterSpacing: 0.4,
    fontWeight: FontWeight.w500,
  );

  static const _dot = Text(
    '·',
    style: TextStyle(color: Color(0xFFB0B8C1), fontSize: 14),
  );

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _FooterTextBtn(label: 'Blog', onTap: openBlog, style: _style),
        _dot,
        _FooterTextBtn(label: 'How to Play', onTap: openHowToPlay, style: _style),
        _dot,
        _FooterTextBtn(label: 'About Us', onTap: openAboutUs, style: _style),
        _dot,
        _FooterTextBtn(
          label: 'Privacy Policy',
          onTap: openPrivacyPolicy,
          style: _style,
        ),
        _dot,
        _FooterTextBtn(label: 'Terms', onTap: openTerms, style: _style),
      ],
    );
  }
}

/// Two balanced rows — no awkward Wrap mid-word gaps on narrow phones.
class _MobileFooterLinks extends StatelessWidget {
  const _MobileFooterLinks();

  static const _style = TextStyle(
    fontSize: 12.5,
    letterSpacing: 0.15,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: Color(0xFF5A6570),
  );

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _FooterTap(label: 'Blog', onTap: openBlog, style: _style),
            _FooterSep(),
            _FooterTap(label: 'How to Play', onTap: openHowToPlay, style: _style),
            _FooterSep(),
            _FooterTap(label: 'About Us', onTap: openAboutUs, style: _style),
          ],
        ),
        SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _FooterTap(
              label: 'Privacy Policy',
              onTap: openPrivacyPolicy,
              style: _style,
            ),
            _FooterSep(),
            _FooterTap(label: 'Terms', onTap: openTerms, style: _style),
          ],
        ),
      ],
    );
  }
}

class _FooterSep extends StatelessWidget {
  const _FooterSep();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '·',
        style: TextStyle(
          color: Color(0xFFB0B8C1),
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}

class _FooterTap extends StatelessWidget {
  const _FooterTap({
    required this.label,
    required this.onTap,
    required this.style,
  });

  final String label;
  final VoidCallback onTap;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Text(label, style: style),
      ),
    );
  }
}

class _FooterTextBtn extends StatelessWidget {
  const _FooterTextBtn({
    required this.label,
    required this.onTap,
    required this.style,
  });

  final String label;
  final VoidCallback onTap;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF5A6570),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      child: Text(label, style: style),
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
    final avatarSize = compact ? 84.0 : 128.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
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
            blurRadius: compact ? 12 : 18,
            offset: Offset(0, compact ? 5 : 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 3,
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
                compact ? 12 : 22,
                compact ? 12 : 18,
                compact ? 12 : 22,
                compact ? 12 : 20,
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
        const SizedBox(width: 24),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const _ChampionBadge(),
              const SizedBox(height: 8),
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
                const SizedBox(height: 12),
                const _ShimmerLine(widthFactor: 0.32, height: 30),
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
                const SizedBox(height: 12),
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
    // Mobile: photo left, identity right — same hierarchy as laptop, shorter card.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            _ChampionBadge(),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Latest Winner',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: HomepagePromoPanel._goldDeep,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (showShimmer)
              _ShimmerCircle(size: avatarSize)
            else
              _WinnerAvatar(photoUrl: photoUrl, size: avatarSize),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showShimmer) ...[
                    const _ShimmerLine(widthFactor: 0.72, height: 16),
                    const SizedBox(height: 10),
                    const _ShimmerLine(widthFactor: 0.48, height: 28),
                  ] else ...[
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: HomepagePromoPanel._ink,
                        fontSize: 18,
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
        ),
      ],
    );
  }
}

class _ChampionBadge extends StatelessWidget {
  const _ChampionBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: HomepagePromoPanel._goldDeep,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33C9A227),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.emoji_events_rounded, size: 13, color: Colors.white),
          SizedBox(width: 5),
          Text(
            'CHAMPION',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF5E6A8), Color(0xFFE8D078)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x55C9A227)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.workspace_premium,
            color: HomepagePromoPanel._goldDeep,
            size: 17,
          ),
          const SizedBox(width: 6),
          Text(
            score > 0 ? 'Score  $score' : 'Score  —',
            style: const TextStyle(
              color: HomepagePromoPanel._goldDeep,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
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

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Container(
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
        ),
        Positioned(
          top: -6,
          child: Icon(
            Icons.workspace_premium,
            color: HomepagePromoPanel._goldDeep.withValues(alpha: 0.95),
            size: 24,
          ),
        ),
      ],
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
        child: Icon(
          Icons.emoji_events_outlined,
          color: Color(0x88C9A227),
          size: 36,
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

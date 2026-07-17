import 'package:flutter/material.dart';

import '../models/confirmed_winner.dart';
import '../models/homepage_config.dart';
import '../platform/homepage_config_cache.dart';
import '../platform/open_url.dart';
import '../services/homepage_config_service.dart';

/// Premium two-column landing block: Offer | Latest Winner.
/// Web home screen only — below the play card, above Privacy.
class HomepagePromoPanel extends StatelessWidget {
  const HomepagePromoPanel({super.key});

  static const surface = Color(0xFFF4F6F8);
  static const _ink = Color(0xFF121820);
  static const _muted = Color(0xFF5A6570);
  static const _offer = Color(0xFFE85D04);
  static const _offerDeep = Color(0xFFC44900);
  static const _gold = Color(0xFFC9A227);
  static const _goldDeep = Color(0xFF8B6914);
  static const _card = Color(0xFFFFFFFF);
  static const _line = Color(0x140A1620);

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final compact = w < 520;
    final side = compact ? 6.0 : 10.0;
    final cachedOffer = readCachedHomepageConfig();

    return ColoredBox(
      color: surface,
      child: StreamBuilder<({HomepageConfig? offer, ConfirmedWinner? winner})>(
        initialData: (offer: cachedOffer, winner: null),
        stream: HomepageConfigService.stream(),
        builder: (context, snapshot) {
          final offer = snapshot.data?.offer ?? cachedOffer;
          final winner = snapshot.data?.winner;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              side,
              compact ? 6 : 8,
              side,
              compact ? 8 : 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (compact)
                  Column(
                    children: [
                      _OfferCard(config: offer),
                      const SizedBox(height: 10),
                      _WinnerCard(winner: winner),
                    ],
                  )
                else
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _OfferCard(config: offer)),
                        const SizedBox(width: 12),
                        Expanded(child: _WinnerCard(winner: winner)),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Privacy link for the Flutter landing footer.
class LandingPrivacyFooter extends StatelessWidget {
  const LandingPrivacyFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: HomepagePromoPanel.surface,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      alignment: Alignment.center,
      child: TextButton(
        onPressed: openPrivacyPolicy,
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF5A6570),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        child: const Text(
          'Privacy Policy',
          style: TextStyle(
            fontSize: 13,
            letterSpacing: 0.4,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.config});

  final HomepageConfig? config;

  @override
  Widget build(BuildContext context) {
    final cfg = config;
    final hasData = cfg?.hasOffer == true;

    return _PromoCardShell(
      accent: HomepagePromoPanel._offer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _MarketHeader(
            badge: 'HOT DEAL',
            title: "Today's Special",
            subtitle: 'Limited-time offer',
            badgeColor: HomepagePromoPanel._offer,
            titleColor: HomepagePromoPanel._offerDeep,
            icon: Icons.local_offer_rounded,
          ),
          if (hasData && cfg!.offerTitle.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              cfg.offerTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: HomepagePromoPanel._ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ],
          const SizedBox(height: 14),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4EC),
                      border: Border.all(color: const Color(0x22E85D04)),
                    ),
                    child: hasData && cfg!.offerImage.isNotEmpty
                        ? Image.network(
                            cfg.offerImage,
                            fit: BoxFit.cover,
                            loadingBuilder: (_, child, progress) {
                              if (progress == null) return child;
                              return const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: HomepagePromoPanel._offer,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) =>
                                const _ImagePlaceholder(
                              icon: Icons.local_offer_outlined,
                              color: HomepagePromoPanel._offer,
                            ),
                          )
                        : const _ImagePlaceholder(
                            icon: Icons.local_offer_outlined,
                            color: HomepagePromoPanel._offer,
                          ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: HomepagePromoPanel._offer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'OFFER',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            hasData && cfg!.offerDesc.isNotEmpty
                ? cfg.offerDesc
                : 'Check back soon for a fresh deal.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: HomepagePromoPanel._muted,
              fontSize: 13.5,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                hasData && cfg!.offerPrice.isNotEmpty ? cfg.offerPrice : '—',
                style: const TextStyle(
                  color: HomepagePromoPanel._offerDeep,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.1,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0x18E85D04),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Grab now',
                  style: TextStyle(
                    color: HomepagePromoPanel._offerDeep,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WinnerCard extends StatelessWidget {
  const _WinnerCard({required this.winner});

  final ConfirmedWinner? winner;

  @override
  Widget build(BuildContext context) {
    final w = winner;
    final hasData = w?.hasWinner == true;
    final name = hasData && w!.name.isNotEmpty ? w.name : 'Coming soon';
    final score = hasData ? w!.score : 0;

    return _PromoCardShell(
      accent: HomepagePromoPanel._gold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _MarketHeader(
            badge: 'CHAMPION',
            title: 'Latest Winner',
            subtitle: 'This week’s top player',
            badgeColor: HomepagePromoPanel._goldDeep,
            titleColor: HomepagePromoPanel._goldDeep,
            icon: Icons.emoji_events_rounded,
            centered: true,
          ),
          const SizedBox(height: 14),
          _WinnerAvatar(photoUrl: w?.photo ?? ''),
          const SizedBox(height: 12),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: HomepagePromoPanel._ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF5E6A8), Color(0xFFE8D078)],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x55C9A227)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.workspace_premium,
                  color: HomepagePromoPanel._goldDeep,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  score > 0 ? 'Score  $score' : 'Score  —',
                  style: const TextStyle(
                    color: HomepagePromoPanel._goldDeep,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MarketHeader extends StatelessWidget {
  const _MarketHeader({
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.badgeColor,
    required this.titleColor,
    required this.icon,
    this.centered = false,
  });

  final String badge;
  final String title;
  final String subtitle;
  final Color badgeColor;
  final Color titleColor;
  final IconData icon;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final align =
        centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = centered ? TextAlign.center : TextAlign.start;

    return Column(
      crossAxisAlignment: align,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: badgeColor,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                badge,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: textAlign,
          style: TextStyle(
            color: titleColor,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: textAlign,
          style: const TextStyle(
            color: HomepagePromoPanel._muted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _PromoCardShell extends StatelessWidget {
  const _PromoCardShell({required this.child, required this.accent});

  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: HomepagePromoPanel._card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HomepagePromoPanel._line),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 3, color: accent),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _WinnerAvatar extends StatelessWidget {
  const _WinnerAvatar({required this.photoUrl});

  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    const size = 88.0;
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
            border: Border.all(color: HomepagePromoPanel._gold, width: 2.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33C9A227),
                blurRadius: 14,
                offset: Offset(0, 4),
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
                    errorBuilder: (_, __, ___) => const _AvatarFallback(),
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return const _AvatarFallback(loading: true);
                    },
                  )
                : const _AvatarFallback(),
          ),
        ),
        Positioned(
          top: -4,
          child: Icon(
            Icons.workspace_premium,
            color: HomepagePromoPanel._goldDeep.withValues(alpha: 0.95),
            size: 22,
          ),
        ),
      ],
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({this.loading = false});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFFFF8E7),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: HomepagePromoPanel._gold,
                ),
              )
            : const Icon(
                Icons.emoji_events_outlined,
                color: Color(0x88C9A227),
                size: 32,
              ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(icon, color: color.withValues(alpha: 0.35), size: 38),
    );
  }
}

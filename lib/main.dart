import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'game/layout_config.dart';
import 'game/config.dart';
import 'game/my_game.dart';
import 'platform/device_type.dart';
import 'platform/fullscreen.dart';
import 'platform/web_shell.dart';
import 'platform/web_splash.dart';
import 'services/homepage_config_service.dart';
import 'services/score_service.dart';
import 'ui/homepage_promo_panel.dart';
import 'ui/leaderboard_panel.dart';
import 'ui/winner_claim_sheet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase core ASAP — Offer/Winner streams must NOT wait for Flame boot.
  HomepageConfigService.warmStart();
  unawaited(ScoreService.instance.ensureFirebaseCore());

  if (kIsWeb) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      hideWebLoadingOverlay();
      // Auth / score warm after first paint (avoids pigeon race on cold load).
      unawaited(ScoreService.instance.init());
    });
  } else {
    unawaited(ScoreService.instance.init());
  }

  if (!kIsWeb) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  final game = MyGame();

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _GameRoot(game: game),
    ),
  );
}

Map<String, Widget Function(BuildContext, MyGame)> _overlayMap({
  bool compactHud = false,
}) =>
    {
      'Hud': (context, game) => _HudOverlay(game: game, compact: compactHud),
      'GameOver': (context, game) => _GameOverOverlay(game: game),
    };

/// Shared [GameWidget] with loading / error states.
class _GameWidget extends StatelessWidget {
  const _GameWidget({
    required this.game,
    required this.canvasKey,
    this.compactHud = false,
  });

  final MyGame game;
  final String canvasKey;
  final bool compactHud;

  @override
  Widget build(BuildContext context) {
    return GameWidget<MyGame>(
      key: ValueKey('game_widget_$canvasKey'),
      game: game,
      initialActiveOverlays: const ['Hud'],
      overlayBuilderMap: _overlayMap(compactHud: compactHud),
      loadingBuilder: (context) => const ColoredBox(
        // Transparent — home StartGate stays visible while Flame boots.
        color: Color(0x00000000),
      ),
      errorBuilder: (context, error) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Game failed to load:\n$error',
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

/// Fixed 914×411 logical world — Flame [FixedResolutionViewport] scales this
/// box uniformly to whatever pixel size the parent provides.
class _FixedWorldBox extends StatelessWidget {
  const _FixedWorldBox({
    required this.game,
    required this.canvasKey,
    this.compactHud = false,
  });

  final MyGame game;
  final String canvasKey;
  final bool compactHud;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: LayoutConfig.referenceWidth,
      height: LayoutConfig.referenceHeight,
      child: ClipRect(
        child: _GameWidget(
          game: game,
          canvasKey: canvasKey,
          compactHud: compactHud,
        ),
      ),
    );
  }
}

/// Desktop / laptop: letterboxed 20:9 frame centred on black (original layout).
class _DesktopCanvas extends StatelessWidget {
  const _DesktopCanvas({required this.game});

  final MyGame game;

  static const _key = 'desktop';

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: LayoutConfig.aspectRatio,
        child: ClipRect(
          child: FittedBox(
            fit: BoxFit.contain,
            child: _FixedWorldBox(game: game, canvasKey: _key),
          ),
        ),
      ),
    );
  }
}

/// Mobile landscape: fill screen edge-to-edge (BoxFit.cover removes side bars).
class _MobileLandscapeCanvas extends StatelessWidget {
  const _MobileLandscapeCanvas({required this.game});

  final MyGame game;

  static const _key = 'mobile';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        if (w < 1 || h < 1) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF31D5FF)),
          );
        }

        return SizedBox(
          width: w,
          height: h,
          child: ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              alignment: Alignment.center,
              child: _FixedWorldBox(
                game: game,
                canvasKey: _key,
                compactHud: true,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GameRoot extends StatefulWidget {
  const _GameRoot({required this.game});

  final MyGame game;

  @override
  State<_GameRoot> createState() => _GameRootState();
}

class _GameRootState extends State<_GameRoot> with WidgetsBindingObserver {
  /// Web: show start gate + landing chrome until the player starts.
  /// Native builds skip the gate and play immediately.
  bool _awaitingStart = kIsWeb;

  /// Defer Flame [GameWidget] until after the first landing paint so Offer /
  /// Winner cards appear instantly. Engine then boots in the background.
  bool _mountGameEngine = !kIsWeb;

  /// Locked at startup — laptop browser resize won't flip mobile/desktop layout.
  late final bool _isMobileDevice;

  DateTime? _lastMetricsRebuild;
  double _lastBuildW = -1;
  double _lastBuildH = -1;

  @override
  void initState() {
    super.initState();
    _isMobileDevice = kIsWeb ? detectMobileWeb() : false;
    if (kIsWeb) {
      WidgetsBinding.instance.addObserver(this);
      widget.game.onExitToHome = _returnToHome;
      // First frame = promo cards + gate UI only. Then mount Flame underneath.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _mountGameEngine) return;
        setState(() => _mountGameEngine = true);
        if (_awaitingStart) {
          widget.game.pauseEngine();
        }
      });
      // Second pass after assets settle — some phones resume during onLoad.
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (mounted && _awaitingStart) {
          widget.game.pauseEngine();
        }
      });
    }
  }

  void _returnToHome() {
    if (!kIsWeb) return;
    exitWebGameplayMode();
    if (!mounted) return;
    setState(() => _awaitingStart = true);
    widget.game.pauseEngine();
  }

  void _startPlaying() {
    if (!_awaitingStart) return;
    if (!widget.game.bootReadyNotifier.value) return;

    widget.game.unlockAudio();
    if (_isMobileDevice) {
      requestBrowserFullscreen();
      lockLandscapeOrientation();
    }
    widget.game.resumeEngine();
    widget.game.refreshSessionBaseTotal();
    unawaited(ScoreService.instance.refreshClaimEligibility());
    // Drop landing chrome (blank + privacy) — immersive game only, market style.
    enterWebGameplayMode();
    setState(() => _awaitingStart = false);
  }

  @override
  void dispose() {
    if (kIsWeb) {
      WidgetsBinding.instance.removeObserver(this);
      widget.game.onExitToHome = null;
    }
    widget.game.disposeNotifiers();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // Browser chrome show/hide fires this often — only rebuild on real size change.
    final now = DateTime.now();
    final last = _lastMetricsRebuild;
    if (last != null && now.difference(last) < const Duration(milliseconds: 160)) {
      return;
    }
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    if ((size.width - _lastBuildW).abs() < 1.5 &&
        (size.height - _lastBuildH).abs() < 1.5) {
      return;
    }
    _lastBuildW = size.width;
    _lastBuildH = size.height;
    _lastMetricsRebuild = now;
    if (mounted) setState(() {});
  }

  bool _useMobileLayout(double shortestSide) {
    if (kIsWeb) return _isMobileDevice;
    return shortestSide < 600;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: (kIsWeb && _awaitingStart)
          ? HomepagePromoPanel.surface
          : Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final maxH = constraints.maxHeight;
          final shortest = maxW < maxH ? maxW : maxH;
          final isPortrait = maxH > maxW;
          final isPhone = _useMobileLayout(shortest);

          final gameStack = _buildGameStack(
            isPhone: isPhone,
            isPortrait: isPortrait,
            maxW: maxW,
            maxH: maxH,
          );

          Widget body;
          // Web landing: premium play card + systematic highlights below.
          if (kIsWeb && _awaitingStart) {
            final viewH = MediaQuery.sizeOf(context).height;
            final compact = maxW < 520;
            // Leave a clear peek of Offer / Winner on first view.
            final gateH = viewH * (compact ? 0.62 : 0.66);
            final sidePad = compact ? 6.0 : 10.0;
            final radius = compact ? 16.0 : 18.0;

            body = ColoredBox(
              color: HomepagePromoPanel.surface,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        sidePad,
                        compact ? 8 : 10,
                        sidePad,
                        compact ? 4 : 6,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(radius),
                          border: Border.all(
                            color: const Color(0x180A1620),
                            width: 1,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x180A1620),
                              blurRadius: 18,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(radius),
                          child: SizedBox(
                            height: gateH,
                            width: double.infinity,
                            child: gameStack,
                          ),
                        ),
                      ),
                    ),
                    const HomepagePromoPanel(),
                    const LandingPrivacyFooter(),
                  ],
                ),
              ),
            );
          } else {
            body = gameStack;
          }

          // Claim CTA overlay — celebration may fire anywhere; button is home-only.
          return Stack(
            fit: StackFit.expand,
            children: [
              body,
              WinnerClaimBanner(
                // Web: home = awaiting start. Native has no gate → always allow button.
                showClaimButton: !kIsWeb || _awaitingStart,
              ),
            ],
          );
      },
    ),
  );
  }

  Widget _buildGameStack({
    required bool isPhone,
    required bool isPortrait,
    required double maxW,
    required double maxH,
  }) {
    // Landing: paint gate first; mount Flame only after [_mountGameEngine]
    // so Offer/Winner are not blocked by engine boot.
    final Widget? playSurface = !_mountGameEngine
        ? null
        : isPhone
            ? (isPortrait
                ? Center(
                    child: RotatedBox(
                      quarterTurns: 1,
                      child: SizedBox(
                        width: maxH,
                        height: maxW,
                        child: _MobileLandscapeCanvas(game: widget.game),
                      ),
                    ),
                  )
                : _MobileLandscapeCanvas(game: widget.game))
            : _DesktopCanvas(game: widget.game);

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        if (playSurface != null) playSurface,
        if (_awaitingStart)
          _StartGate(
            label: isPhone ? 'Tap to Play' : 'Click to Play',
            onStart: _startPlaying,
            bootReadyListenable: widget.game.bootReadyNotifier,
          ),
      ],
    );
  }
}

class _StartGate extends StatelessWidget {
  const _StartGate({
    required this.onStart,
    required this.label,
    required this.bootReadyListenable,
  });

  final VoidCallback onStart;
  final String label;
  final ValueListenable<bool> bootReadyListenable;

  @override
  Widget build(BuildContext context) {
    final showLb = GameConfig.showLeaderboardOnLanding;

    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Landing preview card fill (clipped to rounded parent on home).
          const ColoredBox(color: Colors.black),
          Image.asset(
            'assets/images/landing-preview.png',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            alignment: Alignment.center,
            opacity: const AlwaysStoppedAnimation(0.80),
            errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black),
          ),
          // Soft dark wash so CTA reads clean on the preview.
          const ColoredBox(color: Color(0x59000000)),
          ValueListenableBuilder<bool>(
            valueListenable: bootReadyListenable,
            builder: (_, ready, __) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: ready ? onStart : null,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _GameGlyph(),
                        const SizedBox(height: 14),
                        const _TapHandEmoji(),
                        const SizedBox(height: 16),
                        AnimatedOpacity(
                          opacity: ready ? 1 : 0.72,
                          duration: const Duration(milliseconds: 220),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xE6FFFFFF),
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x33000000),
                                  blurRadius: 16,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ready
                                ? Text(
                                    label,
                                    style: const TextStyle(
                                      color: Color(0xFF0A1218),
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.4,
                                    ),
                                    textAlign: TextAlign.center,
                                  )
                                : const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF0E8FA8),
                                        ),
                                      ),
                                      SizedBox(width: 10),
                                      Text(
                                        'Loading Game Engine…',
                                        style: TextStyle(
                                          color: Color(0xFF0A1218),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          // Landing-only ranks — public when you flip the config flag, or
          // open with ?lb=1 / #lb (admin). Never on Game Over.
          if (showLb)
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: Center(
                child: GestureDetector(
                  onTap: () => LeaderboardPanel.show(context),
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Text(
                      'Leaderboard',
                      style: TextStyle(
                        color: Color(0xFF72F2FF),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        decoration: TextDecoration.underline,
                        decorationColor: Color(0xFF72F2FF),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Simple gamepad glyph — no Material Icons font required.
class _GameGlyph extends StatelessWidget {
  const _GameGlyph();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(64, 40),
      painter: _GameGlyphPainter(),
    );
  }
}

class _GameGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF31D5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round;

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(2, size.height * 0.22, size.width - 4, size.height * 0.56),
      const Radius.circular(12),
    );
    canvas.drawRRect(body, paint);

    // D-pad
    final cx = size.width * 0.28;
    final cy = size.height * 0.50;
    canvas.drawLine(Offset(cx - 7, cy), Offset(cx + 7, cy), paint);
    canvas.drawLine(Offset(cx, cy - 7), Offset(cx, cy + 7), paint);

    // Buttons
    final fill = Paint()..color = const Color(0xFF31D5FF);
    canvas.drawCircle(Offset(size.width * 0.68, size.height * 0.42), 3.2, fill);
    canvas.drawCircle(Offset(size.width * 0.78, size.height * 0.52), 3.2, fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Soft bouncing hand emoji to hint tap.
class _TapHandEmoji extends StatefulWidget {
  const _TapHandEmoji();

  @override
  State<_TapHandEmoji> createState() => _TapHandEmojiState();
}

class _TapHandEmojiState extends State<_TapHandEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  late final Animation<double> _bob = Tween<double>(begin: 0, end: -8).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bob,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, _bob.value),
        child: child,
      ),
      child: const Text('👆', style: TextStyle(fontSize: 42)),
    );
  }
}

class _GameOverGlyph extends StatelessWidget {
  const _GameOverGlyph();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(34, 34),
      painter: _GameOverGlyphPainter(),
    );
  }
}

class _GameOverGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFFFD86A);
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outer = size.width * 0.48;
    final inner = outer * 0.45;
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / 5;
      final b = a + math.pi / 5;
      final ox = cx + outer * math.cos(a);
      final oy = cy + outer * math.sin(a);
      final ix = cx + inner * math.cos(b);
      final iy = cy + inner * math.sin(b);
      if (i == 0) {
        path.moveTo(ox, oy);
      } else {
        path.lineTo(ox, oy);
      }
      path.lineTo(ix, iy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HudOverlay extends StatelessWidget {
  const _HudOverlay({required this.game, this.compact = false});

  final MyGame game;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Extra inset on mobile: BoxFit.cover crops the top-right corner.
    final top = compact ? 18.0 : 10.0;
    final right = compact ? 36.0 : 14.0;

    return SafeArea(
      left: false,
      bottom: false,
      minimum: EdgeInsets.only(top: top, right: right),
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: EdgeInsets.only(top: top * 0.5, right: right * 0.25),
          child: ValueListenableBuilder<int>(
            valueListenable: game.scoreNotifier,
            builder: (_, score, __) {
              return ValueListenableBuilder<int?>(
                valueListenable: game.sessionBaseTotalNotifier,
                builder: (_, sessionTotal, __) {
                  return ValueListenableBuilder<int?>(
                    valueListenable: ScoreService.instance.myTotalNotifier,
                    builder: (_, serviceTotal, __) {
                      // Live service total wins (updates after Firestore submit).
                      // sessionTotal is only a fallback before auth warms.
                      final stored = serviceTotal ?? sessionTotal;
                      return _ScoreBadge(
                        score: score,
                        total: stored,
                        compact: compact,
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Same 1.0→1.04 pulse look, without [ValueKey] recreating the whole subtree
/// on every point (that was GC noise during long runs).
class _ScoreBadge extends StatefulWidget {
  const _ScoreBadge({
    required this.score,
    required this.compact,
    this.total,
  });

  final int score;
  final int? total;
  final bool compact;

  @override
  State<_ScoreBadge> createState() => _ScoreBadgeState();
}

class _ScoreBadgeState extends State<_ScoreBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
  );
  late final Animation<double> _scale = Tween<double>(begin: 1.0, end: 1.04)
      .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeOut));

  @override
  void didUpdateWidget(covariant _ScoreBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.score != widget.score) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.total != null
        ? 'Score: ${widget.score} / ${widget.total}'
        : 'Score: ${widget.score}';

    return AnimatedBuilder(
      animation: _scale,
      builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: TextStyle(
              color: const Color(0xFFF2FAFF),
              fontSize: widget.compact ? 16 : 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 3),
          Container(
            width: widget.total != null
                ? (widget.compact ? 110.0 : 128.0)
                : (widget.compact ? 72.0 : 86.0),
            height: 1,
            color: const Color(0xB3F2FAFF),
          ),
        ],
      ),
    );
  }
}

class _GameOverOverlay extends StatefulWidget {
  const _GameOverOverlay({required this.game});

  final MyGame game;

  @override
  State<_GameOverOverlay> createState() => _GameOverOverlayState();
}

class _GameOverOverlayState extends State<_GameOverOverlay> {
  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    return Material(
      color: const Color(0x99000000),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.85, end: 1.0),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutBack,
          builder: (_, scale, child) => Transform.scale(
            scale: scale,
            child: child,
          ),
          child: Container(
            width: 320,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF171D2E), Color(0xFF222F4A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
                  border:
                      Border.all(color: const Color(0xFF72F2FF), width: 1.4),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x6638D5FF),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ValueListenableBuilder<int>(
              valueListenable: game.scoreNotifier,
              builder: (_, score, __) {
                return ValueListenableBuilder<bool>(
                  valueListenable: game.specialCrashNotifier,
                  builder: (_, showLaughEmoji, __) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                            const _GameOverGlyph(),
                        const SizedBox(height: 8),
                        const Text(
                          'Game Over',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                            ValueListenableBuilder<int?>(
                              valueListenable: game.totalScoreNotifier,
                              builder: (_, submittedTotal, __) {
                                return ValueListenableBuilder<int?>(
                                  valueListenable:
                                      ScoreService.instance.myTotalNotifier,
                                  builder: (_, serviceTotal, __) {
                                    // Prefer post-submit total, then live cache.
                                    final total = submittedTotal ??
                                        serviceTotal ??
                                        game.sessionBaseTotalNotifier.value;
                                    final label = total != null
                                        ? 'Final Score: $score / $total'
                                        : 'Final Score: $score';
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4, horizontal: 8),
                                      child: Text(
                                        label,
                          style: const TextStyle(
                            color: Color(0xFFB6EEFF),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                                        textAlign: TextAlign.center,
                                      ),
                                    );
                                  },
                                );
                              },
                        ),
                        if (showLaughEmoji) ...[
                          const SizedBox(height: 10),
                          const Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '😄😄',
                                  style: TextStyle(fontSize: 28),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'sorry guys',
                                  style: TextStyle(
                                    color: Color(0xFFFFF3C9),
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: game.restartFromOverlay,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF31D5FF),
                              foregroundColor: const Color(0xFF042438),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text(
                              'Restart',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
          ),
          // Web only: small back arrow → home / Tap to Play + Privacy.
          if (kIsWeb)
            Positioned(
              top: 10,
              left: 10,
              child: SafeArea(
                child: GestureDetector(
                  onTap: game.exitToHome,
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: CustomPaint(
                        size: Size(18, 16),
                        painter: _BackArrowPainter(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tiny ← chevron — no Material Icons font required.
class _BackArrowPainter extends CustomPainter {
  const _BackArrowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE8F7FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.62, size.height * 0.12)
      ..lineTo(size.width * 0.22, size.height * 0.5)
      ..lineTo(size.width * 0.62, size.height * 0.88);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

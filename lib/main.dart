import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flame/game.dart';
import 'game/layout_config.dart';
import 'game/my_game.dart';

/// Main entry point for the Flutter application.
///
/// The game canvas is letterboxed inside a fixed aspect-ratio frame that
/// matches the Medium Phone API 36.0 landscape baseline, so desktop Chrome
/// and other resolutions scale uniformly without stretching.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  final game = MyGame();

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: AspectRatio(
            aspectRatio: LayoutConfig.aspectRatio,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: LayoutConfig.referenceWidth,
                height: LayoutConfig.referenceHeight,
                child: GameWidget<MyGame>(
                  game: game,
                  initialActiveOverlays: const ['Hud'],
                  overlayBuilderMap: {
                    'Hud': (context, game) => _HudOverlay(game: game),
                    'GameOver': (context, game) => _GameOverOverlay(game: game),
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _HudOverlay extends StatelessWidget {
  const _HudOverlay({required this.game});

  final MyGame game;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 10, right: 14),
          child: ValueListenableBuilder<int>(
            valueListenable: game.scoreNotifier,
            builder: (_, score, __) {
              return TweenAnimationBuilder<double>(
                key: ValueKey<int>(score),
                tween: Tween<double>(begin: 1.0, end: 1.04),
                duration: const Duration(milliseconds: 120),
                builder: (_, scale, child) => Transform.scale(
                  scale: scale,
                  child: child,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Score: $score',
                      style: const TextStyle(
                        color: Color(0xFFF2FAFF),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      width: 86,
                      height: 1,
                      color: const Color(0xB3F2FAFF),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GameOverOverlay extends StatelessWidget {
  const _GameOverOverlay({required this.game});

  final MyGame game;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x99000000),
      child: Center(
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
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF171D2E), Color(0xFF222F4A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF72F2FF), width: 1.4),
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
                        const Icon(Icons.workspace_premium_rounded,
                            color: Color(0xFFFFD86A), size: 34),
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
                        Text(
                          'Final Score: $score',
                          style: const TextStyle(
                            color: Color(0xFFB6EEFF),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (showLaughEmoji) ...[
                          const SizedBox(height: 10),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                              padding: const EdgeInsets.symmetric(vertical: 12),
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
    );
  }
}

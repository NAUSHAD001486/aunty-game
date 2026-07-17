import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/particles.dart';
import 'package:flutter/foundation.dart';
import '../components/obstacle_manager.dart';
import '../components/player.dart';
import '../platform/device_type.dart';
import '../platform/fullscreen.dart';
import 'game_audio.dart';
import 'layout_config.dart';
import '../services/score_service.dart';

class MyGame extends FlameGame with HasCollisionDetection, TapCallbacks {
  MyGame()
      : super(
          camera: CameraComponent.withFixedResolution(
            width: LayoutConfig.referenceWidth,
            height: LayoutConfig.referenceHeight,
          ),
        );

  Player? _player;
  ObstacleManager? _obstacles;

  SpriteComponent? _background;
  Sprite? _footerSprite;
  final List<SpriteComponent> _footerTiles = [];
  double _footerTileWidth = 0;
  double _footerRightMostX = 0;
  final double _footerScrollSpeed = 140;
  double _footerY = 0;

  int _score = 0;
  final ValueNotifier<int> scoreNotifier = ValueNotifier<int>(0);
  /// Cumulative monthly total after Firestore submit (tap on Game Over to reveal).
  final ValueNotifier<int?> totalScoreNotifier = ValueNotifier<int?>(null);
  /// Stored total at the start of this run — HUD shows run / (base + run).
  final ValueNotifier<int?> sessionBaseTotalNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<bool> specialCrashNotifier = ValueNotifier<bool>(false);
  GameState _state = GameState.playing;

  double _shakeTimer = 0.0;
  bool _isShaking = false;
  final Random _shakeRandom = Random();

  bool _scorePulse = false;
  double _scorePulseTimer = 0.2;
  double _gameOverDelayTimer = 0.2;
  bool _pendingGameOverOverlay = false;
  bool _didSubmitScore = false;

  final GameAudio _audio = GameAudio();
  bool _notifiersDisposed = false;
  bool _didRequestFullscreen = false;

  /// True after boot assets + world are ready (home gate can start play).
  final ValueNotifier<bool> bootReadyNotifier = ValueNotifier<bool>(false);

  /// Fixed logical world — reuse one vector (callers must not mutate it).
  final Vector2 _worldSize = Vector2(
    LayoutConfig.worldWidth,
    LayoutConfig.worldHeight,
  );
  final Vector2 _viewOrigin = Vector2.zero();

  void _lockViewportToReference() {
    camera.viewfinder
      ..anchor = Anchor.topLeft
      ..position = _viewOrigin
      ..zoom = 1.0;
  }

  /// Lightweight park background — world is ~914×411 so the 626px plate is
  /// enough on every platform. Skipping the 6892px plate avoids a multi-second
  /// decode hitch on laptop and mobile.
  String get _backgroundAssetPath => 'character/background.png';

  /// Minimum art for Tap-to-Play + first bamboo pair (rest loads after).
  static const _bootAssets = [
    'character/background.png',
    'character/background/roted.png',
    'character/5-character.png',
    'character/out/1-out.png',
  ];

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    _lockViewportToReference();

    // Critical path — 4 images instead of 9. Jump frames + 2nd bamboo defer.
    await Future.wait(_bootAssets.map(images.load));

    // Sound + extra sprites while user is on Tap to Play / first seconds.
    unawaited(_audio.load());
    unawaited(_warmDeferredAssets());

    // ================= BACKGROUND =================
    final bgPath = _backgroundAssetPath;
    final bgImage = images.fromCache(bgPath);
    _background = SpriteComponent(
      sprite: Sprite(bgImage),
      anchor: Anchor.center,
    );
    _background!.opacity = 0.80;
    _background!.priority = -20;

    add(_background!);
    _fitBackground(_worldSize);

    // ================= FOOTER LOOP (ROTED WOOD RING) =================
    final footerImage = images.fromCache('character/background/roted.png');
    _footerSprite = Sprite(footerImage);
    _buildFooterLoop(_worldSize);

    // ================= PLAYER =================
    final player = Player();
    player.onCrashed = _triggerGameOver;
    _player = player;
    add(player);

    player.initPosition(_worldSize);

    // ================= OBSTACLES =================
    final obstacles = ObstacleManager(
      onScore: _addScore,
    );

    _obstacles = obstacles;
    add(obstacles);

    debugPrint('[MyGame] Loaded');
    bootReadyNotifier.value = true;
    refreshSessionBaseTotal();
  }

  /// Pull this player's saved total so the live HUD can show run / DB total.
  void refreshSessionBaseTotal() {
    unawaited(() async {
      final cached = ScoreService.instance.myTotalNotifier.value;
      if (cached != null && !_notifiersDisposed) {
        sessionBaseTotalNotifier.value = cached;
      }

      int? total;
      for (var i = 0; i < 8; i++) {
        total = await ScoreService.instance.fetchMyTotalScore();
        if (total != null) break;
        await Future<void>.delayed(Duration(milliseconds: 350 * (i + 1)));
      }
      if (_notifiersDisposed) return;
      // After game-over submit, that path owns the notifiers — don't clobber.
      if (_didSubmitScore) return;
      if (total != null) {
        sessionBaseTotalNotifier.value = total;
      } else if (sessionBaseTotalNotifier.value == null) {
        sessionBaseTotalNotifier.value = cached ?? 0;
      }
    }());
  }

  void _submitScoreOnce() {
    if (_didSubmitScore) return;
    _didSubmitScore = true;
    final runScore = _score;

    // Optimistic UI: show accumulated total immediately (base + this run).
    // Prefer live/service total; never assume 0 while auth is still warming.
    final base = sessionBaseTotalNotifier.value ??
        ScoreService.instance.myTotalNotifier.value;
    final optimistic =
        runScore == 0 ? (base ?? 0) : (base ?? 0) + runScore;
    totalScoreNotifier.value = optimistic;
    if (base != null || runScore > 0) {
      sessionBaseTotalNotifier.value = optimistic;
      // Persist locally NOW so F5 keeps the sum even if Firestore is slow/fails.
      ScoreService.instance.rememberLocalTotal(optimistic);
    }

    unawaited(() async {
      final total = await ScoreService.instance.submitRunScore(runScore);
      if (_notifiersDisposed) return;
      if (total != null) {
        totalScoreNotifier.value = total;
        sessionBaseTotalNotifier.value = total;
        ScoreService.instance.rememberLocalTotal(total);
      }
      // If submit failed, keep optimistic so the player still sees run+base.
    }());
  }

  Future<void> _warmDeferredAssets() async {
    try {
      await Future.wait([
        images.load('character/1-character.png'),
        images.load('character/2-character.png'),
        images.load('character/3-character.png'),
        images.load('character/4-character.png'),
        images.load('character/out/2-out.png'),
      ]);
    } catch (e) {
      debugPrint('[MyGame] deferred assets: $e');
    }
  }

  // FULLSCREEN BACKGROUND FIT
  void _fitBackground(Vector2 gameSize) {
    if (_background == null) return;

    final img = _background!.sprite!.image;

    final imgRatio = img.width / img.height;
    final screenRatio = gameSize.x / gameSize.y;

    if (screenRatio > imgRatio) {
      _background!.size = Vector2(gameSize.x, gameSize.x / imgRatio);
    } else {
      _background!.size = Vector2(gameSize.y * imgRatio, gameSize.y);
    }

    _background!.position = gameSize / 2;
  }

  void _buildFooterLoop(Vector2 gameSize) {
    final sprite = _footerSprite;
    if (sprite == null) return;

    // World size is fixed — never thrash tiles on browser chrome resize.
    if (_footerTiles.isNotEmpty) return;

    final footerHeight = LayoutConfig.heightOf(
      LayoutConfig.footerBaseHeightFactor * LayoutConfig.footerScaleMultiplier,
      gameSize.y,
    );
    final image = sprite.image;
    final scale = footerHeight / image.height;
    _footerTileWidth = image.width * scale;
    _footerY = gameSize.y -
        footerHeight +
        (footerHeight * LayoutConfig.footerVerticalInsetFactor);

    final tileCount = (gameSize.x / _footerTileWidth).ceil() + 2;
    for (int i = 0; i < tileCount; i++) {
      final tile = SpriteComponent(
        sprite: sprite,
        anchor: Anchor.topLeft,
        position: Vector2(i * _footerTileWidth, _footerY),
        size: Vector2(_footerTileWidth, footerHeight),
      );
      tile.opacity = 0.5; // 50% visible
      tile.priority = -10; // behind bamboo/obstacles
      _footerTiles.add(tile);
      add(tile);
    }
    _footerRightMostX = (tileCount - 1) * _footerTileWidth;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);

    _lockViewportToReference();

    _fitBackground(_worldSize);
    // Footer is fixed-world — skip rebuild (was destroying/recreating tiles).
    _buildFooterLoop(_worldSize);

    final p = _player;
    if (p != null && p.isMounted) {
      p.updateBaseX(
        LayoutConfig.widthOf(LayoutConfig.playerXFactor, _worldSize.x),
      );
    }
  }

  @override
  void update(double dt) {
    // Cap large frame spikes (tab switch / GC) so physics don't teleport.
    if (dt > 1 / 30) dt = 1 / 30;

    if (_state == GameState.playing && _footerTiles.isNotEmpty) {
      // Keep ground scroll matched to bamboo speed so the world feels one piece.
      final move =
          _footerScrollSpeed * (_obstacles?.speedScale ?? 1.0) * dt;
      final width = _footerTileWidth;
      for (final tile in _footerTiles) {
        tile.x -= move;
      }
      _footerRightMostX -= move;
      for (final tile in _footerTiles) {
        if (tile.x + width < 0) {
          tile.x = _footerRightMostX + width;
          _footerRightMostX = tile.x;
        }
      }
    }

    if (_isShaking) {
      _shakeTimer -= dt;
      if (_shakeTimer <= 0) {
        _isShaking = false;
        camera.viewfinder.position.setZero();
      } else {
        camera.viewfinder.position.setValues(
          (_shakeRandom.nextDouble() - .5) * 6,
          (_shakeRandom.nextDouble() - .5) * 6,
        );
      }
    }

    if (_scorePulse) {
      _scorePulseTimer -= dt;
      if (_scorePulseTimer <= 0) _scorePulse = false;
    }

    if (_pendingGameOverOverlay) {
      _gameOverDelayTimer -= dt;
      if (_gameOverDelayTimer <= 0) {
        _pendingGameOverOverlay = false;
        _state = GameState.gameOver;
        overlays.add('GameOver');
      }
    }

    super.update(dt);
  }

  @override
  Color backgroundColor() => const Color(0xFF87CEFA);

  /// Unlock Web Audio on the first real user gesture (required on mobile).
  void unlockAudio() => unawaited(_audio.unlock());

  @override
  bool onTapDown(TapDownEvent event) {
    // Fullscreen once is enough for play; re-locking / re-requesting every
    // jump triggers browser work and feels like a hitch mid-game.
    if (kIsWeb && detectMobileWeb() && !_didRequestFullscreen) {
      _didRequestFullscreen = true;
      requestBrowserFullscreen();
    }
    if (_state == GameState.gameOver) {
      if (kIsWeb) unlockAudio();
      _resetGame();
      return true;
    }

    if (_state == GameState.crashing) return true;
    if (_state != GameState.playing) return true;

    _player?.jump();
    _audio.playJump();
    return true;
  }

  void _addScore(int points) {
    if (_state != GameState.playing || points <= 0) return;

    _score += points;
    scoreNotifier.value = _score;
    _scorePulse = true;
    _scorePulseTimer = .15;

    _obstacles?.applyScoreProgress(_score);

    _audio.playScore();
    if (kDebugMode) {
      debugPrint('Score $_score');
    }
  }

  void _triggerGameOver(Vector2? crashPoint) {
    if (_state != GameState.playing) return;

    if (crashPoint != null) {
      _spawnFireImpact(crashPoint);
    }

    _state = GameState.crashing;

    _player?.playCrashAnimation();
    _obstacles?.setFrozen(true);

    _shakeTimer = .40;
    _isShaking = true;

    final specialCrash = _audio.playCrash();
    specialCrashNotifier.value = specialCrash;
    _gameOverDelayTimer = 1.0;
    _pendingGameOverOverlay = true;
    _submitScoreOnce();
  }

  void _spawnFireImpact(Vector2 worldPoint) {
    // Compact red flash at exact touch point.
    add(ParticleSystemComponent(
      position: worldPoint.clone(),
      particle: CircleParticle(
        lifespan: 0.07,
        radius: 10,
        paint: Paint()..color = const Color(0xE6FF9A9A),
      ),
    ));

    // Main compact flame burst in red shades (finer particles).
    add(ParticleSystemComponent(
      position: worldPoint.clone(),
      particle: Particle.generate(
        count: 28,
        lifespan: 0.42,
        generator: (_) {
          final speed = Vector2(
            (_shakeRandom.nextDouble() - 0.5) * 150,
            -(_shakeRandom.nextDouble() * 280 + 90),
          );
          return AcceleratedParticle(
            acceleration: Vector2(0, 720),
            speed: speed,
            child: CircleParticle(
              radius: 0.9 + _shakeRandom.nextDouble() * 1.2,
              paint: Paint()
                ..color = Color.lerp(
                      const Color(0xFFFF8C8C),
                      const Color(0xCCCF1010),
                      _shakeRandom.nextDouble(),
                    ) ??
                    const Color(0xCCE03535),
            ),
          );
        },
      ),
    ));

    // Short red embers + dark smoke, limited spread.
    add(TimerComponent(
      period: 0.08,
      repeat: true,
      tickCount: 4,
      removeOnFinish: true,
      onTick: () {
        add(ParticleSystemComponent(
          position: worldPoint.clone(),
          particle: Particle.generate(
            count: 8,
            lifespan: 0.36,
            generator: (index) {
              final ember = index.isEven;
              final speed = Vector2(
                (_shakeRandom.nextDouble() - 0.5) * (ember ? 110 : 70),
                -(_shakeRandom.nextDouble() * (ember ? 150 : 90) + 20),
              );
              return AcceleratedParticle(
                acceleration: Vector2(0, ember ? 560 : 140),
                speed: speed,
                child: CircleParticle(
                  radius: ember
                      ? (0.45 + _shakeRandom.nextDouble() * 0.9)
                      : (1.1 + _shakeRandom.nextDouble() * 1.0),
                  paint: Paint()
                    ..color = ember
                        ? (Color.lerp(
                              const Color(0xE6FF7B7B),
                              const Color(0xD9C81010),
                              _shakeRandom.nextDouble(),
                            ) ??
                            const Color(0xD9E03030))
                        : const Color(0x2E301515),
                ),
              );
            },
          ),
        ));
      },
    ));
  }

  void _resetGame() {
    _state = GameState.playing;

    _shakeTimer = 0;
    _isShaking = false;
    camera.viewfinder.position.setZero();

    _score = 0;
    scoreNotifier.value = _score;
    // After a submitted run, that total becomes the new base for the next HUD.
    final submitted = totalScoreNotifier.value;
    totalScoreNotifier.value = null;
    if (submitted != null) {
      sessionBaseTotalNotifier.value = submitted;
    } else {
      refreshSessionBaseTotal();
    }
    specialCrashNotifier.value = false;
    _scorePulse = false;
    _gameOverDelayTimer = 0;
    _pendingGameOverOverlay = false;
    _didSubmitScore = false;

    _obstacles?.reset();
    _obstacles?.setFrozen(false);

    _player?.reset(gameSize: _worldSize);
    overlays.remove('GameOver');
  }

  void restartFromOverlay() {
    if (_state == GameState.gameOver) {
      _resetGame();
    }
  }

  /// Soft return to the web home / Tap-to-Play gate (no full page reload).
  VoidCallback? onExitToHome;

  void exitToHome() {
    if (_state == GameState.crashing) {
      _pendingGameOverOverlay = false;
      _gameOverDelayTimer = 0;
    }
    _resetGame();
    pauseEngine();
    onExitToHome?.call();
  }

  /// Called once when the app shell is destroyed — NOT from [onRemove], because
  /// [GameWidget] can unmount/remount on browser resize without destroying the game.
  void disposeNotifiers() {
    if (_notifiersDisposed) return;
    _notifiersDisposed = true;
    scoreNotifier.dispose();
    totalScoreNotifier.dispose();
    sessionBaseTotalNotifier.dispose();
    specialCrashNotifier.dispose();
    bootReadyNotifier.dispose();
  }
}

enum GameState { playing, crashing, gameOver }

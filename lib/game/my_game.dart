import 'dart:math';
import 'dart:ui';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/particles.dart';
import 'package:flutter/foundation.dart';
import '../components/obstacle_manager.dart';
import '../components/player.dart';
import 'game_audio.dart';
import 'layout_config.dart';

class MyGame extends FlameGame with HasCollisionDetection, TapCallbacks {
  MyGame()
      : super(
          camera: CameraComponent.withFixedResolution(
            width: LayoutConfig.referenceWidth,
            height: LayoutConfig.referenceHeight,
          ),
        );

  /// World bounds used for canvas clipping — nothing renders outside this rect.
  late final Vector2 _clipSize;
  Player? _player;
  ObstacleManager? _obstacles;

  SpriteComponent? _background;
  Sprite? _footerSprite;
  final List<SpriteComponent> _footerTiles = [];
  double _footerTileWidth = 0;
  final double _footerScrollSpeed = 140;
  double _footerY = 0;

  int _score = 0;
  final ValueNotifier<int> scoreNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> specialCrashNotifier = ValueNotifier<bool>(false);
  GameState _state = GameState.playing;

  double _shakeTimer = 0.0;
  bool _isShaking = false;
  final Random _shakeRandom = Random();

  bool _scorePulse = false;
  double _scorePulseTimer = 0.2;
  double _gameOverDelayTimer = 0.2;
  bool _pendingGameOverOverlay = false;

  final GameAudio _audio = GameAudio();

  /// Fixed logical world size — never use the canvas [size] from [onGameResize].
  Vector2 get _worldSize =>
      Vector2(LayoutConfig.worldWidth, LayoutConfig.worldHeight);

  void _lockViewportToReference() {
    camera.viewfinder
      ..anchor = Anchor.topLeft
      ..position = Vector2.zero()
      ..zoom = 1.0;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    _clipSize = Vector2(LayoutConfig.worldWidth, LayoutConfig.worldHeight);
    _lockViewportToReference();

    await _audio.load();

    // ================= BACKGROUND =================
    final bgImage =
        await images.load('character/background/background.png');

    _background = SpriteComponent(
      sprite: Sprite(bgImage),
      anchor: Anchor.center,
    );
    _background!.priority = -20;

    add(_background!);
    _fitBackground(_worldSize);

    // ================= FOOTER LOOP (ROTED WOOD RING) =================
    final footerImage = await images.load('character/background/roted.png');
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
      onPlayerPassedObstacle: _incrementScore,
    );

    _obstacles = obstacles;
    add(obstacles);

    debugPrint('[MyGame] Loaded');
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

    for (final tile in _footerTiles) {
      tile.removeFromParent();
    }
    _footerTiles.clear();

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
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);

    // Canvas [size] is the browser widget; world layout always uses reference.
    _lockViewportToReference();

    final world = _worldSize;
    _fitBackground(world);
    _buildFooterLoop(world);

    final p = _player;
    if (p != null && p.isMounted) {
      p.updateBaseX(LayoutConfig.widthOf(LayoutConfig.playerXFactor, world.x));
    }
  }

  @override
  void update(double dt) {
    if (_state == GameState.playing && _footerTiles.isNotEmpty) {
      final move = _footerScrollSpeed * dt;
      for (final tile in _footerTiles) {
        tile.x -= move;
      }

      for (final tile in _footerTiles) {
        if (tile.x + _footerTileWidth < 0) {
          double rightMostX = _footerTiles.first.x;
          for (final other in _footerTiles) {
            if (other.x > rightMostX) {
              rightMostX = other.x;
            }
          }
          tile.x = rightMostX + _footerTileWidth;
        }
      }
    }

    if (_isShaking) {
      _shakeTimer -= dt;
      if (_shakeTimer <= 0) {
        _isShaking = false;
        camera.viewfinder.position = Vector2.zero();
      } else {
        camera.viewfinder.position = Vector2(
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
  bool onTapDown(TapDownEvent event) {
    if (_state == GameState.gameOver) {
      _resetGame();
      return true;
    }

    if (_state == GameState.crashing) return true;
    if (_state != GameState.playing) return true;

    _player?.jump();
    _audio.playJump();
    return true;
  }

  void _incrementScore() {
    if (_state != GameState.playing) return;

    _score++;
    scoreNotifier.value = _score;
    _scorePulse = true;
    _scorePulseTimer = .15;

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
        count: 54,
        lifespan: 0.48,
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
            count: 14,
            lifespan: 0.40,
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
    camera.viewfinder.position = Vector2.zero();

    _score = 0;
    scoreNotifier.value = _score;
    specialCrashNotifier.value = false;
    _scorePulse = false;
    _gameOverDelayTimer = 0;
    _pendingGameOverOverlay = false;

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

  @override
  void onRemove() {
    scoreNotifier.dispose();
    specialCrashNotifier.dispose();
    super.onRemove();
  }

  /// Clip all rendering to the fixed world bounds so no sprites bleed onto the
  /// letterbox area.  Called every frame by Flame before children are painted.
  @override
  void render(Canvas canvas) {
    canvas.clipRect(
      Rect.fromLTWH(0, 0, _clipSize.x, _clipSize.y),
      clipOp: ClipOp.intersect,
    );
    super.render(canvas);
  }
}

enum GameState { playing, crashing, gameOver }

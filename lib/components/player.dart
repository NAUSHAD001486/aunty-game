import 'dart:async';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import '../game/config.dart';
import '../game/layout_config.dart';

class Player extends PositionComponent
    with CollisionCallbacks, HasGameRef {
  double _velocityY = 0.0;
  double _baseX = 0.0;
  bool _frozen = false;
  bool _isCrashAnimating = false;
  double _crashAnimTimer = 0.0;

  void Function(Vector2?)? onCrashed;

  late SpriteAnimationComponent _visual;
  late SpriteAnimation _idleAnimation;
  SpriteAnimation? _jumpAnimation;

  bool _isJumpAnimating = false;
  bool _jumpFramesReady = false;

  Player()
      : super(
          size: Vector2(80, 120),
          anchor: Anchor.center,
        );

  static const _idleAsset = 'character/5-character.png';
  static const _jumpAssets = [
    'character/1-character.png',
    'character/2-character.png',
    'character/3-character.png',
    'character/4-character.png',
  ];

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Idle frame is preloaded by [MyGame] boot set — no duplicate decode.
    final idleImg = game.images.containsKey(_idleAsset)
        ? game.images.fromCache(_idleAsset)
        : await game.images.load(_idleAsset);
    _idleAnimation = SpriteAnimation.spriteList(
      [Sprite(idleImg)],
      stepTime: 0.10,
      loop: true,
    );

    _visual = SpriteAnimationComponent(
      animation: _idleAnimation,
      anchor: Anchor.center,
      position: Vector2(size.x / 2, size.y / 2),
    );
    _visual.scale = Vector2.all(0.8);
    add(_visual);

    // Jump cycle loads in background during Tap-to-Play / landing scroll.
    unawaited(_loadJumpFrames());

    addAll([
      RectangleHitbox(
        position: Vector2(size.x * 1.19, size.y * -0.60),
        size: Vector2(size.x * 0.22, size.y * 0.14),
      ),
      RectangleHitbox(
        position: Vector2(size.x * 0.07, size.y * -0.21),
        size: Vector2(size.x * 1.84, size.y * 0.17),
      ),
      RectangleHitbox(
        position: Vector2(size.x * -0.98, size.y * 0.26),
        size: Vector2(size.x * 0.68, size.y * 0.30),
      ),
      RectangleHitbox(
        position: Vector2(size.x * -0.48, size.y * -0.04),
        size: Vector2(size.x * 0.45, size.y * 0.42),
      ),
       RectangleHitbox(
        position: Vector2(size.x * -0.68, size.y * 0.08),
        size: Vector2(size.x * 0.40, size.y * 0.40),
      ),
       RectangleHitbox(
        position: Vector2(size.x * -0.28, size.y * -0.08),
        size: Vector2(size.x * 0.40, size.y * 0.40),
      ),
       RectangleHitbox(
        position: Vector2(size.x * -0.04, size.y * -0.18),
        size: Vector2(size.x * 0.45, size.y * 0.47),
      ),
       RectangleHitbox(
        position: Vector2(size.x * 0.18, size.y * -0.28),
        size: Vector2(size.x * 0.40, size.y * 0.49),
      ),
       RectangleHitbox(
        position: Vector2(size.x * 0.38, size.y * -0.38),
        size: Vector2(size.x * 0.40, size.y * 0.40),
      ),
       RectangleHitbox(
        position: Vector2(size.x * 0.58, size.y * -0.48),
        size: Vector2(size.x * 0.40, size.y * 0.40),
      ),
       RectangleHitbox(
        position: Vector2(size.x * 0.72, size.y * -0.48),
        size: Vector2(size.x * 0.40, size.y * 0.40),
      ),
    ]);
  }

  Future<void> _loadJumpFrames() async {
    if (_jumpFramesReady) return;
    try {
      final frames = await Future.wait(
        _jumpAssets.map((path) async {
          if (game.images.containsKey(path)) {
            return game.images.fromCache(path);
          }
          return game.images.load(path);
        }),
      );
      _jumpAnimation = SpriteAnimation.spriteList(
        frames.map(Sprite.new).toList(),
        stepTime: 1 / 14,
        loop: false,
      );
      _jumpFramesReady = true;
    } catch (_) {
      // Idle-only fallback — gameplay still works.
    }
  }

  void initPosition(Vector2 gameSize) {
    _baseX = LayoutConfig.widthOf(LayoutConfig.playerXFactor, gameSize.x);
    position = Vector2(
      _baseX,
      LayoutConfig.heightOf(LayoutConfig.playerYFactor, gameSize.y),
    );
    _velocityY = 0;
    _isJumpAnimating = false;
  }

  void updateBaseX(double x) => _baseX = x;

  @override
  void update(double dt) {
    super.update(dt);
    if (_frozen) return;

    final screenH = LayoutConfig.worldHeight;

    _velocityY += GameConfig.gravity * dt;
    if (_velocityY > GameConfig.maxFallSpeed) {
      _velocityY = GameConfig.maxFallSpeed;
    }

    position.y += _velocityY * dt;

    if (position.y < size.y / 2) {
      position.y = size.y / 2;
    }

    if (position.y > screenH + GameConfig.fallOutBelowWorld) {
      onCrashed?.call(null);
      return;
    }

    position.x = _baseX;

    if (_isJumpAnimating &&
        (_visual.animationTicker?.done() ?? false)) {
      _visual.animation = _idleAnimation;
      _isJumpAnimating = false;
    }

    if (_isCrashAnimating) {
      _crashAnimTimer -= dt;
      angle += 3.0 * dt;
      if (_crashAnimTimer <= 0) {
        _isCrashAnimating = false;
        _frozen = true;
      }
    }
  }

  void jump() {
    if (_frozen) return;

    if (_velocityY > 0) _velocityY = 0;
    _velocityY = GameConfig.jumpImpulse;

    final jumpAnim = _jumpAnimation;
    if (jumpAnim != null && !_isJumpAnimating) {
      _visual.animation = jumpAnim;
      _visual.animationTicker?.reset();
      _isJumpAnimating = true;
    } else if (!_jumpFramesReady) {
      unawaited(_loadJumpFrames());
    }
  }

  void setFrozen(bool frozen) => _frozen = frozen;

  void playCrashAnimation() {
    if (_isCrashAnimating) return;
    _isCrashAnimating = true;
    _crashAnimTimer = 0.65;
    _frozen = false;
    _isJumpAnimating = false;
    _velocityY = -220;
  }

  void reset({required Vector2 gameSize}) {
    position.y = LayoutConfig.heightOf(LayoutConfig.playerYFactor, gameSize.y);
    _velocityY = 0;
    _isJumpAnimating = false;
    _isCrashAnimating = false;
    _crashAnimTimer = 0;
    _frozen = false;
    angle = 0;

    _visual.animation = _idleAnimation;
    _visual.animationTicker?.reset();
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (_frozen) return;
    final hitPoint = intersectionPoints.isNotEmpty
        ? intersectionPoints.first
        : position + size / 2;
    onCrashed?.call(hitPoint);
  }
}
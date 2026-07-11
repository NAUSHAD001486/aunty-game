import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/sprite.dart';
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
  late SpriteAnimation _jumpAnimation;
  late SpriteAnimation _idleAnimation;

  bool _isJumpAnimating = false;

  Player()
      : super(
          size: Vector2(80, 120),
          anchor: Anchor.center,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final frames = [
      await game.images.load('character/1-character.png'),
      await game.images.load('character/2-character.png'),
      await game.images.load('character/3-character.png'),
      await game.images.load('character/4-character.png'),
      await game.images.load('character/5-character.png'),
    ];

    // TRUE 21 FPS (video synced)
    _jumpAnimation = SpriteAnimation.spriteList(
      frames.take(4).map(Sprite.new).toList(),
      stepTime: 1 / 14,
      loop: false,
    );

    _idleAnimation = SpriteAnimation.spriteList(
      [Sprite(frames.last)],
      stepTime: 0.10,
      loop: true,
    );

    _visual = SpriteAnimationComponent(
      animation: _idleAnimation,
      anchor: Anchor.center,
      position: Vector2(size.x / 2, size.y / 2), // center visual on hitbox
    );

    _visual.scale = Vector2.all(0.2);

    add(_visual);
    // Split collision into body parts so tilted sprite gets a tighter fit.
    addAll([
      // Head + shoulder area(left hand sabse upar)
      RectangleHitbox(
        position: Vector2(size.x * 1.19, size.y * -0.60),
        size: Vector2(size.x * 0.22, size.y * 0.14),
      ),
      // Chest / torso (right hand niche wala hand)
      RectangleHitbox(
        position: Vector2(size.x * 0.07, size.y * -0.21),
        size: Vector2(size.x * 1.84, size.y * 0.17),
      ),
      // Waist / upper legs (last pair ka hissa (1))
      RectangleHitbox(
        position: Vector2(size.x * -0.98, size.y * 0.26),
        size: Vector2(size.x * 0.68, size.y * 0.30),
      ),
      // Lower dress / pair ka 3 number hai  (3)
      RectangleHitbox(
        position: Vector2(size.x * -0.48, size.y * -0.04),
        size: Vector2(size.x * 0.45, size.y * 0.42),
      ),
      // pair ka 2 number  (2)
       RectangleHitbox(
        position: Vector2(size.x * -0.68, size.y * 0.08),
        size: Vector2(size.x * 0.40, size.y * 0.40),
      ),
      //pair ka 4 number  (4)

       RectangleHitbox(
        position: Vector2(size.x * -0.28, size.y * -0.08),
        size: Vector2(size.x * 0.40, size.y * 0.40),
      ),
      //pair ka 5 number   (5)

       RectangleHitbox(
        position: Vector2(size.x * -0.04, size.y * -0.18),
        size: Vector2(size.x * 0.45, size.y * 0.47),
      ),
      // pair ka 6 number.  (6)
       RectangleHitbox(
        position: Vector2(size.x * 0.18, size.y * -0.28),
        size: Vector2(size.x * 0.40, size.y * 0.49),
      ),
      //pair ka 7 number   (7)
       RectangleHitbox(
        position: Vector2(size.x * 0.38, size.y * -0.38),
        size: Vector2(size.x * 0.40, size.y * 0.40),
      ),
      //pair ka 8 number (8)
       RectangleHitbox(
        position: Vector2(size.x * 0.58, size.y * -0.48),
        size: Vector2(size.x * 0.40, size.y * 0.40),
      ),
      // pair ka 9 number   (9)
       RectangleHitbox(
        position: Vector2(size.x * 0.72, size.y * -0.48),
        size: Vector2(size.x * 0.40, size.y * 0.40),
      ),
    ]);
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

    if (position.y > screenH + 80) {
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

    if (!_isJumpAnimating) {
      _visual.animation = _jumpAnimation;
      _visual.animationTicker?.reset();
      _isJumpAnimating = true;
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

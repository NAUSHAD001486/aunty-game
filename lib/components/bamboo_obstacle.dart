import 'dart:async';
import 'dart:ui' as ui;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

/// Bamboo obstacle with hitboxes derived from **baked** stalk fractions.
///
/// Pixel scanning via [Image.toByteData] used to freeze load for seconds on
/// web/mobile. Bounds were computed offline from the same algorithm and are
/// identical for current `1-out.png` / `2-out.png` art — gameplay unchanged.
class BambooObstacle extends SpriteComponent with CollisionCallbacks {
  /// Asset file name only, e.g. `1-out.png`.
  final String variant;

  BambooObstacle({
    required Sprite sprite,
    required Anchor anchor,
    required Vector2 position,
    required Vector2 size,
    required this.variant,
  }) : super(
          sprite: sprite,
          anchor: anchor,
          position: position,
          size: size,
        );

  /// Offline scan results (normalized stalk rect in source image space).
  static const Map<String, ui.Rect> _bakedStalk = {
    '1-out.png': ui.Rect.fromLTWH(
      0.3740234375,
      0.083984375,
      0.298828125,
      0.81640625,
    ),
    '2-out.png': ui.Rect.fromLTWH(
      0.326171875,
      0.0830078125,
      0.302734375,
      0.8193359375,
    ),
  };

  @override
  FutureOr<void> onLoad() {
    // Sync path — no await — avoids a mid-run frame hitch on every spawn.
    _attachHitboxes(_bakedStalk[variant]);
    return super.onLoad();
  }

  void _attachHitboxes(ui.Rect? bounds) {
    if (bounds != null) {
      double fractX = bounds.left;
      double fractY = bounds.top;
      double fractW = bounds.width;
      double fractH = bounds.height;

      // Keep stalk hitbox tight: slight width expansion only.
      const double widthBoost = 0.06;
      fractX -= widthBoost / 2;
      fractW += widthBoost;

      final isFlipped = scale.y < 0; // top bamboo is flipped
      if (isFlipped) {
        final extend = fractH * 0.02;
        fractY -= extend;
        fractH += extend;
      } else {
        const double topTrim = 0.12;
        fractY += topTrim;
        fractH -= topTrim;
      }

      {
        const double minH = 180;
        const double maxH = 960;
        const double midH = (minH + maxH) / 2;
        final t = ((size.y - midH) / (maxH - midH)).clamp(-1.0, 1.0);
        final heightScale = t < 0 ? 1.0 + 0.05 * t : 1.0 + 0.02 * t;

        final center = fractY + fractH / 2;
        fractH *= heightScale;
        fractY = center - fractH / 2;
      }

      if (fractX < 0) fractX = 0;
      if (fractY < 0) fractY = 0;
      if (fractX + fractW > 1) fractW = 1 - fractX;
      if (fractY + fractH > 1) fractH = 1 - fractY;

      final hitboxX = fractX * size.x;
      final hitboxY = fractY * size.y;
      final hitboxW = fractW * size.x;
      final hitboxH = fractH * size.y;

      final leftW = hitboxW * 0.50;
      final rightW = hitboxW - leftW;

      addAll([
        RectangleHitbox(
          position: Vector2(hitboxX + hitboxW * 0.19, hitboxY + hitboxH * 0.12),
          size: Vector2(leftW * 1.05, hitboxH * 0.96),
          anchor: Anchor.topLeft,
          isSolid: true,
        ),
        RectangleHitbox(
          position:
              Vector2(hitboxX + leftW + hitboxW * -0.19, hitboxY + hitboxH * 0.01),
          size: Vector2(rightW * 0.95, hitboxH * 0.97),
          anchor: Anchor.topLeft,
          isSolid: true,
        ),
      ]);
    } else {
      addAll([
        RectangleHitbox(
          size: Vector2(size.x * 0.5, size.y),
          position: Vector2.zero(),
          anchor: Anchor.topLeft,
          isSolid: true,
        ),
        RectangleHitbox(
          size: Vector2(size.x * 0.5, size.y),
          position: Vector2(size.x * 0.5, 0),
          anchor: Anchor.topLeft,
          isSolid: true,
        ),
      ]);
    }
  }
}

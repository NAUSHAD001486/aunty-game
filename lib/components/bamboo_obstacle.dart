import 'dart:ui' as ui;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

/// Reusable bamboo obstacle with **pixel-perfect** collision hitbox.
///
/// Uses a smart two-pass pixel scan:
///   Pass 1 – Column density (8 % threshold) → finds the bamboo
///            stalk's X range, excluding thin side leaves.
///   Pass 2 – Within that X range, scans every row for ANY content
///            pixel (no row threshold) → captures the full stalk
///            height including the narrow opening / tip.
///
/// Each instance (bottom / top) gets its own independent hitbox that
/// exactly follows its bamboo stalk dimensions — width AND height.
class BambooObstacle extends SpriteComponent with CollisionCallbacks {
  static final Map<String, Future<ui.Rect?>> _stalkBoundsCache = {};

  BambooObstacle({
    required Sprite sprite,
    required Anchor anchor,
    required Vector2 position,
    required Vector2 size,
  }) : super(
          sprite: sprite,
          anchor: anchor,
          position: position,
          size: size,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final spr = sprite;
    if (spr == null) return;

    final bounds = await _getOrScanStalkBounds(spr);

    if (bounds != null) {
      final srcW = spr.srcSize.x;
      final srcH = spr.srcSize.y;

      double fractX = bounds.left / srcW;
      double fractY = bounds.top / srcH;
      double fractW = bounds.width / srcW;
      double fractH = bounds.height / srcH;

      // Keep stalk hitbox tight: slight width expansion only.
      const double widthBoost = 0.06;
      fractX -= widthBoost / 2;
      fractW += widthBoost;

      // ── Height fine-tune based on orientation ──
      final isFlipped = scale.y < 0; // top bamboo is flipped
      if (isFlipped) {
        // Small extension so top tip stays covered.
        final extend = fractH * 0.02;
        fractY -= extend;
        fractH += extend;
      } else {
        // Trim top section where leaf/noise pixels inflate bounds.
        const double topTrim = 0.12;
        fractY += topTrim;
        fractH -= topTrim;
      }

      // ── Mild height scaling: small bamboo −5 %, large bamboo +2 % ──
        // Linearly interpolates based on component height so the
        // hitbox height matches the visual bamboo across all sizes.
        {
          const double minH = 180; // shortest possible bamboo
          const double maxH = 960; // tallest possible bamboo
          const double midH = (minH + maxH) / 2; // 370
          final t = ((size.y - midH) / (maxH - midH)).clamp(-1.0, 1.0);
          // t = -1 → small (×0.95), t = 0 → mid (×1.0), t = +1 → large (×1.02)
          final heightScale = t < 0
              ? 1.0 + 0.05 * t   // small side: up to -5%
              : 1.0 + 0.02 * t;  // large side: up to +2%

        // Scale around the hitbox center so it stays aligned
        final center = fractY + fractH / 2;
        fractH *= heightScale;
        fractY = center - fractH / 2;
      }

      // Clamp to valid 0–1 range
      if (fractX < 0) fractX = 0;
      if (fractY < 0) fractY = 0;
      if (fractX + fractW > 1) fractW = 1 - fractX;
      if (fractY + fractH > 1) fractH = 1 - fractY;

      // Split one bamboo into 2 side-by-side hitboxes for easier manual tuning.
      final hitboxX = fractX * size.x;
      final hitboxY = fractY * size.y;
      final hitboxW = fractW * size.x;
      final hitboxH = fractH * size.y;

      final leftW = hitboxW * 0.50;
      final rightW = hitboxW - leftW;

      // Manual-friendly multipliers (x/y/width/height) like player hitboxes.
      addAll([
        RectangleHitbox(
          position: Vector2(hitboxX + hitboxW * 0.19, hitboxY + hitboxH * 0.12),//x se bamboo right side jata hai
          size: Vector2(leftW * 1.05, hitboxH * 0.96),
          anchor: Anchor.topLeft,
          isSolid: true,
        ),
        RectangleHitbox(
          position: Vector2(hitboxX + leftW + hitboxW * -0.19, hitboxY + hitboxH * 0.01),
          size: Vector2(rightW * 0.95, hitboxH * 0.97),
          anchor: Anchor.topLeft,
          isSolid: true,
        ),
      ]);
    } else {
      // Fallback: still keep 2-part hitboxes so tuning behavior stays consistent.
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

  // ─────────────────────────────────────────────────────────────────
  //  Two-pass pixel scan  (cached per sprite source rect)
  // ─────────────────────────────────────────────────────────────────
  static Future<ui.Rect?> _getOrScanStalkBounds(Sprite spr) {
    final image = spr.image;
    final srcX = spr.srcPosition.x.toInt();
    final srcY = spr.srcPosition.y.toInt();
    final srcW = spr.srcSize.x.toInt();
    final srcH = spr.srcSize.y.toInt();
    final cacheKey = '${image.hashCode}:$srcX:$srcY:$srcW:$srcH';

    return _stalkBoundsCache.putIfAbsent(
      cacheKey,
      () => _scanStalkBounds(
        image: image,
        srcX: srcX,
        srcY: srcY,
        srcW: srcW,
        srcH: srcH,
      ),
    );
  }

  /// **Pass 1** — Full-image column density scan.
  ///   Counts content pixels per column.  Columns with ≥ 8 % fill
  ///   define the stalk's X range (thin side-leaves are excluded).
  ///
  /// **Pass 2** — Focused Y-extent scan *only* within the stalk
  ///   X range found in Pass 1.  Every row that contains at least
  ///   one content pixel inside the stalk range extends the Y bounds
  ///   (no row-density threshold).  This captures the narrow bamboo
  ///   opening / tip that Pass 1's column density already includes.
  ///
  /// Result: hitbox width = stalk width (no leaves), hitbox height =
  /// full stalk from tip to base (including narrow opening).
  static Future<ui.Rect?> _scanStalkBounds({
    required ui.Image image,
    required int srcX,
    required int srcY,
    required int srcW,
    required int srcH,
  }) async {
    final byteData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) return null;

    final pixels = byteData.buffer.asUint8List();
    final imgW = image.width;

    // Background reference from top-left corner
    final bgIdx = (srcY * imgW + srcX) * 4;
    final bgR = pixels[bgIdx];
    final bgG = pixels[bgIdx + 1];
    final bgB = pixels[bgIdx + 2];
    final bgA = pixels[bgIdx + 3];
    final bool transparentBg = bgA < 128;

    // ── Pass 1: column density → stalk X range ──────────────────
    final colDensity = List<int>.filled(srcW, 0);

    for (int y = 0; y < srcH; y++) {
      for (int x = 0; x < srcW; x++) {
        final idx = ((srcY + y) * imgW + (srcX + x)) * 4;
        final a = pixels[idx + 3];
        if (a < 15) continue;

        if (!transparentBg) {
          final r = pixels[idx];
          final g = pixels[idx + 1];
          final b = pixels[idx + 2];
          final dist = (r - bgR) * (r - bgR) +
              (g - bgG) * (g - bgG) +
              (b - bgB) * (b - bgB);
          if (dist < 1500) continue;
        }

        colDensity[x]++;
      }
    }

    final colThresh = (srcH * 0.08).round();
    int minX = srcW, maxX = -1;

    for (int x = 0; x < srcW; x++) {
      if (colDensity[x] >= colThresh) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
      }
    }

    if (maxX < minX) return null;

    // ── Pass 2: within stalk X range, find full Y extent ────────
    // No row threshold — even a single content pixel in the stalk
    // column range extends the Y bounds.  This includes the narrow
    // bamboo opening / tip that density filtering would cut off.
    int minY = srcH, maxY = -1;

    for (int y = 0; y < srcH; y++) {
      for (int x = minX; x <= maxX; x++) {
        final idx = ((srcY + y) * imgW + (srcX + x)) * 4;
        final a = pixels[idx + 3];
        if (a < 15) continue;

        if (!transparentBg) {
          final r = pixels[idx];
          final g = pixels[idx + 1];
          final b = pixels[idx + 2];
          final dist = (r - bgR) * (r - bgR) +
              (g - bgG) * (g - bgG) +
              (b - bgB) * (b - bgB);
          if (dist < 1500) continue;
        }

        // Found a content pixel in the stalk range for this row
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        break; // move to next row
      }
    }

    if (maxY < minY) return null;

    return ui.Rect.fromLTWH(
      minX.toDouble(),
      minY.toDouble(),
      (maxX - minX + 1).toDouble(),
      (maxY - minY + 1).toDouble(),
    );
  }
}

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../game/config.dart';

/// A single runner-style obstacle: a simple rectangle moving left.
///
/// This component is designed for pooling:
/// - It can be reset/reused without allocating new objects in update loops.
/// - It moves left at a constant speed until it is off-screen.
class Obstacle extends RectangleComponent with CollisionCallbacks {
  Obstacle({
    required Paint paint,
  }) : _paint = paint,
       super(anchor: Anchor.topLeft, paint: paint);

  final Paint _paint;

  // True once onLoad has completed and hitbox is ready.
  bool _ready = false;

  // Current movement state.
  bool _active = false;
  bool _frozen = false;

  // For scoring (increment once when passed).
  bool _scored = false;

  bool get isActive => _active;

  /// Returns true if this obstacle has fully moved off-screen to the left.
  bool isOffScreenLeft(double screenWidth) {
    // When right edge is left of 0, it's off-screen.
    return position.x + size.x < 0;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Add hitbox for collision detection (created once).
    add(RectangleHitbox());

    // Start inactive; manager will reset() before use.
    _active = false;

    // Mark this obstacle as ready for safe reset() calls.
    _ready = true;
  }

  /// Reset this obstacle to a new configuration (pool-friendly).
  ///
  /// - [worldSize]: Current game world size (pixels).
  /// - [x]: Starting x position (typically just off the right edge).
  /// - [y]: Vertical position (top of obstacle).
  /// - [width]: Obstacle width.
  /// - [height]: Obstacle height.
  void reset({
    required Vector2 worldSize,
    required double x,
    required double y,
    required double width,
    required double height,
  }) {
    // Guard against reset() being called before onLoad() has completed.
    if (!_ready) {
      return;
    }

    // Set obstacle size and position.
    size = Vector2(width, height);
    position = Vector2(x, y);

    _scored = false;
    _active = true;
  }

  /// Freeze/unfreeze movement (used during game over).
  void setFrozen(bool frozen) {
    _frozen = frozen;
  }

  /// Deactivate this obstacle (returned to pool).
  void deactivate() {
    _active = false;
  }

  /// Check and mark score when the player passes this obstacle.
  ///
  /// Returns true once when the obstacle is passed.
  bool tryScore(double playerX) {
    if (_scored || !_active) {
      return false;
    }

    // Player has passed when player's x is beyond obstacle's right edge.
    final obstacleRight = position.x + size.x;
    if (playerX > obstacleRight) {
      _scored = true;
      return true;
    }

    return false;
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (!_active || _frozen) {
      return;
    }

    // Move left at constant speed.
    position.x -= GameConfig.obstacleSpeed * dt;
  }
}



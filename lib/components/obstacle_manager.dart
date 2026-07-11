import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../game/config.dart';
import '../game/layout_config.dart';
import 'bamboo_obstacle.dart';

class ObstacleManager extends Component with HasGameRef {
  final VoidCallback onPlayerPassedObstacle;

  ObstacleManager({required this.onPlayerPassedObstacle});

  final Random _rand = Random();

  BambooObstacle? _bottom;
  BambooObstacle? _midTop;

  /// Old pipes still moving off-screen (cleanup list)
  final List<BambooObstacle> _oldPipes = [];
  final Set<BambooObstacle> _scoredPipes = {};

  double _speed = GameConfig.obstacleSpeed;
  double _lastPipeWidth = 120;
  bool _isSpawning = false;

  /// Locked world bounds — never read [gameRef.size] for layout.
  static const double _screenW = LayoutConfig.referenceWidth;
  static const double _screenH = LayoutConfig.referenceHeight;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _spawn();
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (_bottom == null || _midTop == null) return;

    final move = _speed * dt;

    _bottom!.x -= move;
    _midTop!.x -= move;

    for (final pipe in _oldPipes) {
      pipe.x -= move;
    }

    final playerX = LayoutConfig.widthOf(LayoutConfig.playerXFactor, _screenW);
    _tryScorePipe(_bottom!, playerX);
    _tryScorePipe(_midTop!, playerX);
    for (final pipe in _oldPipes) {
      _tryScorePipe(pipe, playerX);
    }

    for (int i = _oldPipes.length - 1; i >= 0; i--) {
      final pipe = _oldPipes[i];
      if (pipe.x < -_lastPipeWidth * 2) {
        _scoredPipes.remove(pipe);
        pipe.removeFromParent();
        _oldPipes.removeAt(i);
      }
    }

    if (!_isSpawning &&
        _bottom!.x <
            LayoutConfig.widthOf(LayoutConfig.respawnTriggerXFactor, _screenW)) {
      _spawn();
    }
  }

  Future<void> _spawn() async {
    if (_isSpawning) return;
    _isSpawning = true;
    try {
      final img = _rand.nextBool() ? '1-out.png' : '2-out.png';
      final sprite = Sprite(await game.images.load('character/out/$img'));

      if (_bottom != null) _oldPipes.add(_bottom!);
      if (_midTop != null) _oldPipes.add(_midTop!);

      const screenH = _screenH;
      const screenW = _screenW;

      final topPipeHeightFactor = LayoutConfig.topPipeMinHeightFactor +
          _rand.nextDouble() * LayoutConfig.topPipeHeightRangeFactor;

      final derivedBottomFactor =
          1.0 - topPipeHeightFactor - LayoutConfig.gapHeightFactor;
      final randomBottomFactor = LayoutConfig.minBottomHeightFactor +
          _rand.nextDouble() * LayoutConfig.bottomHeightRangeFactor;
      final useDerivedGap = derivedBottomFactor >=
              LayoutConfig.minBottomHeightFactor &&
          derivedBottomFactor <=
              LayoutConfig.minBottomHeightFactor +
                  LayoutConfig.bottomHeightRangeFactor;
      final bottomHeight = LayoutConfig.heightOf(
        useDerivedGap ? derivedBottomFactor : randomBottomFactor,
        screenH,
      );

      final topPipeHeight = LayoutConfig.heightOf(topPipeHeightFactor, screenH);

      final realWidth = sprite.image.width.toDouble();
      final double pipeWidth =
          img == '2-out.png' ? realWidth * 0.105 : realWidth * 0.35;

      _lastPipeWidth = pipeWidth;

      const startX = screenW;
      final zigzagOffset =
          LayoutConfig.widthOf(LayoutConfig.zigzagOffsetFactor, screenW);
      final verticalOffset =
          LayoutConfig.heightOf(LayoutConfig.verticalOffsetFactor, screenH);
      final topY =
          LayoutConfig.heightOf(LayoutConfig.topPipeAnchorYFactor, screenH);

      _bottom = BambooObstacle(
        sprite: sprite,
        anchor: Anchor.bottomCenter,
        position: Vector2(startX, screenH + verticalOffset),
        size: Vector2(pipeWidth, bottomHeight),
      );

      _midTop = BambooObstacle(
        sprite: sprite,
        anchor: Anchor.topCenter,
        position: Vector2(startX + zigzagOffset, topY),
        size: Vector2(pipeWidth, topPipeHeight),
      )..flipVertically();

      addAll([_bottom!, _midTop!]);
    } finally {
      _isSpawning = false;
    }
  }

  void _tryScorePipe(BambooObstacle pipe, double playerX) {
    if (_scoredPipes.contains(pipe)) return;
    final rightEdge = pipe.x + (pipe.size.x / 2);
    if (rightEdge < playerX) {
      _scoredPipes.add(pipe);
      onPlayerPassedObstacle();
    }
  }

  void reset() {
    _bottom?.removeFromParent();
    _midTop?.removeFromParent();
    for (final pipe in _oldPipes) {
      pipe.removeFromParent();
    }
    _oldPipes.clear();
    _scoredPipes.clear();
    _bottom = null;
    _midTop = null;

    _speed = GameConfig.obstacleSpeed;
    _spawn();
  }

  void setFrozen(bool frozen) {
    _speed = frozen ? 0 : GameConfig.obstacleSpeed;
  }
}

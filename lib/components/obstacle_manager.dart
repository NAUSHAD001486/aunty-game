import 'dart:async';
import 'dart:math';
import 'package:flame/components.dart';
import '../game/config.dart';
import '../game/layout_config.dart';
import 'bamboo_obstacle.dart';

class ObstacleManager extends Component with HasGameRef {
  /// Points to add when the player clears one bamboo pair.
  final void Function(int points) onScore;

  ObstacleManager({required this.onScore});

  final Random _rand = Random();

  BambooObstacle? _bottom;
  BambooObstacle? _midTop;

  /// Old pipes still moving off-screen (cleanup list)
  final List<BambooObstacle> _oldPipes = [];
  final Set<BambooObstacle> _scoredPipes = {};

  /// Bottoms only — each pair awards +1 exactly once (never the top stalk).
  final Set<BambooObstacle> _scoreTriggers = {};

  Sprite? _sprite1;
  Sprite? _sprite2;

  double _runSpeed = GameConfig.obstacleSpeed;
  double _speed = GameConfig.obstacleSpeed;
  bool _frozen = false;
  bool _isSpawning = false;
  bool _spawnNextFrame = false;

  /// 1.0 at start → rises toward max as score grows (for footer sync).
  double get speedScale => _runSpeed / GameConfig.obstacleSpeed;

  /// Locked world bounds — never read [gameRef.size] for layout.
  static const double _screenW = LayoutConfig.referenceWidth;
  static const double _screenH = LayoutConfig.referenceHeight;

  static final double _playerX =
      LayoutConfig.widthOf(LayoutConfig.playerXFactor, _screenW);
  static final double _respawnX =
      LayoutConfig.widthOf(LayoutConfig.respawnTriggerXFactor, _screenW);

  /// Center-to-center travel before the next pair (keeps current difficulty).
  static final double _pairTravel = _screenW - _respawnX;

  /// Spawn X of the active bottom (so off-screen entry doesn't change spacing).
  double _activeSpawnX = _screenW;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final path1 = 'character/out/1-out.png';
    final img1 = game.images.containsKey(path1)
        ? game.images.fromCache(path1)
        : await game.images.load(path1);
    _sprite1 = Sprite(img1);
    _spawn();
    unawaited(_loadSecondBambooSprite());
  }

  Future<void> _loadSecondBambooSprite() async {
    try {
      const path = 'character/out/2-out.png';
      final img = game.images.containsKey(path)
          ? game.images.fromCache(path)
          : await game.images.load(path);
      _sprite2 = Sprite(img);
    } catch (_) {}
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Spread spawn cost onto a quiet frame (avoids hitch with score same frame).
    if (_spawnNextFrame) {
      _spawnNextFrame = false;
      _spawn();
    }

    if (_bottom == null || _midTop == null) return;

    final move = _speed * dt;

    _bottom!.x -= move;
    _midTop!.x -= move;

    for (final pipe in _oldPipes) {
      pipe.x -= move;
    }

    // One score event per bamboo pair (+1), including demoted old bottoms.
    _tryScoreActivePair();
    for (final pipe in _oldPipes) {
      _tryScoreTrigger(pipe);
    }

    // Cull as soon as fully off-screen (center + half-width < 0).
    // Old threshold (-2× width) kept dead pipes + hitboxes alive for seconds
    // and stuttered after closer spawn densified on-screen pairs.
    for (int i = _oldPipes.length - 1; i >= 0; i--) {
      final pipe = _oldPipes[i];
      if (pipe.x + pipe.size.x * 0.5 < 0) {
        _scoredPipes.remove(pipe);
        _scoreTriggers.remove(pipe);
        pipe.removeFromParent();
        _oldPipes.removeAt(i);
      }
    }

    if (!_isSpawning &&
        !_spawnNextFrame &&
        _bottom!.x < _activeSpawnX - _pairTravel) {
      _spawnNextFrame = true;
    }
  }

  /// Scores the current top+bottom pair once when the lower stalk clears.
  void _tryScoreActivePair() {
    final bottom = _bottom;
    if (bottom == null) return;
    _tryScoreTrigger(bottom);
  }

  void _tryScoreTrigger(BambooObstacle pipe) {
    if (!_scoreTriggers.contains(pipe)) return;
    if (_scoredPipes.contains(pipe)) return;
    final rightEdge = pipe.x + (pipe.size.x / 2);
    if (rightEdge < _playerX) {
      _scoredPipes.add(pipe);
      onScore(1);
    }
  }

  void _spawn() {
    if (_isSpawning) return;
    final sprite1 = _sprite1;
    if (sprite1 == null) return;

    _isSpawning = true;
    try {
      final sprite2 = _sprite2;
      final useSecond = sprite2 != null && _rand.nextBool();
      final sprite = useSecond ? sprite2 : sprite1;
      final img = useSecond ? '2-out.png' : '1-out.png';

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

      // Lock on-screen bamboo width to original art metrics.
      final double pipeWidth =
          img == '2-out.png' ? 3264 * 0.105 : 1024 * 0.35;

      // Center-anchored: place fully off the right edge so it slides in
      // (old startX = screenW put half the stalk on-screen instantly = "pop").
      final startX = screenW + pipeWidth * 0.5;
      _activeSpawnX = startX;
      final zigzagOffset =
          LayoutConfig.widthOf(LayoutConfig.zigzagOffsetFactor, screenW);
      final verticalOffset =
          LayoutConfig.heightOf(LayoutConfig.verticalOffsetFactor, screenH);
      final topY =
          LayoutConfig.heightOf(LayoutConfig.topPipeAnchorYFactor, screenH);

      _bottom = BambooObstacle(
        sprite: sprite,
        variant: img,
        anchor: Anchor.bottomCenter,
        position: Vector2(startX, screenH + verticalOffset),
        size: Vector2(pipeWidth, bottomHeight),
      );
      _scoreTriggers.add(_bottom!);

      _midTop = BambooObstacle(
        sprite: sprite,
        variant: img,
        anchor: Anchor.topCenter,
        position: Vector2(startX + zigzagOffset, topY),
        size: Vector2(pipeWidth, topPipeHeight),
      )..flipVertically();

      addAll([_bottom!, _midTop!]);
    } finally {
      _isSpawning = false;
    }
  }

  /// Score 0–1: base speed. Score 2,4,6…: add [GameConfig.speedBumpAmount] each time.
  void applyScoreProgress(int score) {
    final steps = score ~/ GameConfig.speedBumpEveryScore;
    // 1.5 → +15 px/s so the requested step feels good in-game.
    final bumped = GameConfig.obstacleSpeed +
        steps * GameConfig.speedBumpAmount * 10.0;
    _runSpeed = bumped.clamp(
      GameConfig.obstacleSpeed,
      GameConfig.obstacleSpeedMax,
    );
    if (!_frozen) {
      _speed = _runSpeed;
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
    _scoreTriggers.clear();
    _bottom = null;
    _midTop = null;

    _frozen = false;
    _runSpeed = GameConfig.obstacleSpeed;
    _speed = _runSpeed;
    _spawn();
  }

  void setFrozen(bool frozen) {
    _frozen = frozen;
    // Resume at the ramped speed, not the base — or progress would reset mid-run.
    _speed = frozen ? 0 : _runSpeed;
  }
}

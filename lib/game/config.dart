/// Game configuration constants
///
/// This file contains all game-wide configuration values
/// such as colors, physics tuning, and gameplay constants.
class GameConfig {
  /// Background color (RGB 0–255)
  static const int backgroundColorR = 135;
  static const int backgroundColorG = 206;
  static const int backgroundColorB = 250;

  /// Player configuration
  static const double playerWidth = 96.0;
  static const double playerHeight = 96.0;

  /// =======================
  /// VERTICAL PHYSICS (FLAPPY-STYLE)
  /// =======================

  /// Gravity acceleration (px/s²) - pulls player DOWN (positive Y)
  static const double gravity = 1300.0;

  /// Jump impulse (negative = UP, positive = DOWN)
  static const double jumpImpulse = -480.0;

  /// Max falling speed (px/s)
  static const double maxFallSpeed = 700.0;

  /// =======================
  /// OBSTACLES (LANDSCAPE RUNNER)
  /// =======================

  /// Horizontal speed of obstacles moving LEFT (px/s)
  static const double obstacleSpeed = 220.0;

  /// Spawn interval (seconds)
  static const double obstacleSpawnInterval = 1.6;

  /// Width of obstacle rectangles (px)
  static const double obstacleWidth = 70.0;

  /// Height of obstacle rectangles (px)
  static const double obstacleHeight = 120.0;

  /// Minimum Y position for obstacle spawning (px)
  static const double obstacleMinY = 50.0;

  /// Prevent instantiation
  GameConfig._();
}

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

  /// How far below the world bottom the player may fall before OUT.
  /// - Smaller number → OUT earlier (line moves **up**)
  /// - Larger number → OUT later (line moves **down**)
  /// Was 80; lowered so character does not fall so deep before dying.
  static const double fallOutBelowWorld = 40.0;

  /// =======================
  /// OBSTACLES (LANDSCAPE RUNNER)
  /// =======================

  /// Horizontal speed of obstacles at start (px/s).
  static const double obstacleSpeed = 220.0;

  /// Soft cap — late game stays playable.
  static const double obstacleSpeedMax = 360.0;

  /// Bump on score 2, 4, 6, … (every N points).
  static const int speedBumpEveryScore = 1;

  /// Each bump adds this much (your **1.5**).
  /// In-game: +15 px/s per bump (`1.5 × 10`) so it feels clear but smooth.
  static const double speedBumpAmount = 2.0;

  /// Spawn interval (seconds)
  static const double obstacleSpawnInterval = 1.6;

  /// Width of obstacle rectangles (px)
  static const double obstacleWidth = 70.0;

  /// Height of obstacle rectangles (px)
  static const double obstacleHeight = 120.0;

  /// Minimum Y position for obstacle spawning (px)
  static const double obstacleMinY = 50.0;

  /// When `true`, everyone sees a Leaderboard link on the pre-play landing / Tap screen.
  /// Keep `false` so only you (admin) can open it via `?lb=1` in the URL.
  static const bool leaderboardPublicOnLanding = false;

  /// True when the landing-page Leaderboard link should appear.
  static bool get showLeaderboardOnLanding {
    if (leaderboardPublicOnLanding) return true;
    // Admin unlock for this session: yoursite.com/?lb=1 or #lb
    final uri = Uri.base;
    if (uri.queryParameters['lb'] == '1') return true;
    if (uri.fragment == 'lb') return true;
    return false;
  }

  /// Prevent instantiation
  GameConfig._();
}

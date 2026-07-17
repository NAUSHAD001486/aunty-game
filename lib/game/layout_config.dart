/// Layout baseline locked to **Medium Phone API 36.0** (Android 16 Baklava).
///
/// AVD hardware profile (`config.ini`):
/// - Portrait pixels: 1080 × 2400
/// - Density: 420 dpi
/// - Landscape logical size (Flutter game coordinates):
///   width  = 2400 × (160 / 420) ≈ 914.29
///   height = 1080 × (160 / 420) ≈ 411.43
///
/// All proportions below were extracted from the pixel values that render
/// perfectly on that emulator. Multiplying a factor by [referenceHeight] or
/// [referenceWidth] reproduces the exact tuned layout at the baseline.
class LayoutConfig {
  LayoutConfig._();

  static const int _hardwareWidth = 1080;
  static const int _hardwareHeight = 2400;
  static const int _lcdDensity = 420;

  /// Landscape logical width on the reference emulator.
  static const double referenceWidth =
      _hardwareHeight * 160 / _lcdDensity; // ~914.286

  /// Landscape logical height on the reference emulator.
  static const double referenceHeight =
      _hardwareWidth * 160 / _lcdDensity; // ~411.429

  /// Width / height for [AspectRatio] and viewport locking.
  static const double aspectRatio = referenceWidth / referenceHeight;

  // ---------------------------------------------------------------------------
  // Bamboo / obstacle proportions (from tuned reference pixels)
  // ---------------------------------------------------------------------------

  /// Vertical corridor between top & bottom bamboo (original tuned `gap = 240`).
  /// - Smaller number → gap **closes** (harder)
  /// - Larger number → gap **opens** (easier)
  static const double gapHeightFactor = 180 / referenceHeight;

  static const double minBottomHeightFactor = 180 / referenceHeight;
  static const double bottomHeightRangeFactor = 0.35;
  static const double verticalOffsetFactor = 40 / referenceHeight;

  static const double zigzagOffsetFactor = 420 / referenceWidth;

  static const double topPipeMinHeightFactor = 320 / referenceHeight;
  static const double topPipeHeightRangeFactor = 240 / referenceHeight;
  static const double topPipeAnchorYFactor = 0.50;

  static const double respawnTriggerXFactor = 0.10;
  static const double playerXFactor = 0.30;
  static const double playerYFactor = 0.60;

  // Footer wood ring (original: 82px base, ×1.25 scale)
  static const double footerBaseHeightFactor = 82 / referenceHeight;
  static const double footerScaleMultiplier = 1.25;
  static const double footerVerticalInsetFactor = 0.15;

  /// Converts a normalized height slice into pixels for the active game size.
  static double heightOf(double factor, double screenHeight) =>
      factor * screenHeight;

  /// Converts a normalized width slice into pixels for the active game size.
  static double widthOf(double factor, double screenWidth) => factor * screenWidth;

  /// Immutable world size — always use this instead of [gameRef.size] or
  /// the canvas size passed to [onGameResize] (which varies per platform).
  static double get worldWidth => referenceWidth;
  static double get worldHeight => referenceHeight;
}

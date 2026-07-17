import 'package:web/web.dart' as web;

/// True for phone/tablet browsers — stable across window resize on laptop.
bool detectMobileWeb() {
  final ua = web.window.navigator.userAgent.toLowerCase();
  // iPadOS 13+ can report as Macintosh while still being touch-first.
  final iPadDesktopUa = web.window.navigator.maxTouchPoints > 1 &&
      ua.contains('macintosh');
  return ua.contains('android') ||
      ua.contains('iphone') ||
      ua.contains('ipad') ||
      ua.contains('ipod') ||
      ua.contains('mobile') ||
      iPadDesktopUa;
}

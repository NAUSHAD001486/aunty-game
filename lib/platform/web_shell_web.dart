import 'package:web/web.dart' as web;

/// Market-style immersive play: lock the viewport to the game only.
void enterWebGameplayMode() {
  final body = web.document.body;
  final html = web.document.documentElement;
  if (body == null) return;
  if (body.classList.contains('is-playing')) return;

  body.classList.add('is-playing');
  html?.classList.add('is-playing');
  html?.scrollTop = 0;
  body.scrollTop = 0;
}

/// Restore the pre-play landing scroll (promo + privacy live in Flutter).
void exitWebGameplayMode() {
  final body = web.document.body;
  final html = web.document.documentElement;
  if (body == null) return;

  body.classList.remove('is-playing');
  html?.classList.remove('is-playing');
  html?.scrollTop = 0;
  body.scrollTop = 0;
}

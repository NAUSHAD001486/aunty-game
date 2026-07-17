import 'package:web/web.dart' as web;

/// Removes the HTML landing shell (or legacy `#loading`) once Flutter paints.
void hideWebLoadingOverlay() {
  web.document.getElementById('landing-shell')?.remove();
  web.document.getElementById('loading')?.remove();
}
